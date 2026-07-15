#!/usr/bin/env bash
# Prepara sysroot Python Android para cross-compilação (maturin/PyO3 e C/C++).
# Versão AGNÓSTICA: nenhum literal de versão/arch. Tudo derivado dos argumentos.
# Original de referência: prepare-android-python.sh (mantido intocado).
set -euo pipefail

ARCH="${1:-aarch64}"
ANDROID_API="${2:-24}"
PY="${3:-3.12}"
SYSROOT_DIR="${SYSROOT_DIR:-${RUNNER_TEMP:-/tmp}/termux-android-sysroot}"
EXTRACT_DIR="${SYSROOT_DIR}/extracted"

# Deriva PYMAJ/PYMIN/CP-TAG a partir do argumento "3.12" -> 3, 12, cp312
PY="${PY#python}"            # tolera "python3.12"
PYMAJ="${PY%%.*}"
PYMIN="${PY#*.}"
PYMIN="${PYMIN%%.*}"
CPTAG="cp${PYMAJ}${PYMIN}"
PYTAG="${PYMAJ}.${PYMIN}"     # 3.12

case "$ARCH" in
  aarch64) TRIPLE="aarch64-linux-android";       ABI_DOT="arm64-v8a" ;;
  x86_64)  TRIPLE="x86_64-linux-android";        ABI_DOT="x86-64" ;;
  armv7l)  TRIPLE="armv7a-linux-androideabi";    ABI_DOT="armeabi-v7a" ;;
  i686)    TRIPLE="i686-linux-android";          ABI_DOT="x86" ;;
  *) echo "❌ Arch não suportada: $ARCH"; exit 1 ;;
esac

vassert() { [ -n "$1" ] || { echo "❌ variável vazia (BUG agnóstico): $2"; exit 1; }; }
vassert "$PYMAJ"  "PYMAJ"; vassert "$PYMIN"  "PYMIN"
vassert "$CPTAG" "CPTAG"; vassert "$TRIPLE" "TRIPLE"

create_stub() {
    echo "   Criando libpython stub para linker (Py ${PY}, ${TRIPLE})..."
    mkdir -p "$SYSROOT_DIR/lib" "$SYSROOT_DIR/lib/python${PYTAG}"
    NDK_BIN="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin"
    case "$ARCH" in
      aarch64) CC="${NDK_BIN}/aarch64-linux-android${ANDROID_API}-clang" ;;
      x86_64)  CC="${NDK_BIN}/x86_64-linux-android${ANDROID_API}-clang" ;;
      armv7l)  CC="${NDK_BIN}/armv7a-linux-androideabi${ANDROID_API}-clang" ;;
      i686)    CC="${NDK_BIN}/i686-linux-android${ANDROID_API}-clang" ;;
    esac

    cat > "${RUNNER_TEMP:-/tmp}/pystub_${PYTAG}_${ARCH}.c" << 'CEOF'
int Py_IsInitialized() { return 0; }
void Py_Initialize() {}
void Py_Finalize() {}
void* PyImport_ImportModule(const char *n) { return 0; }
CEOF
    "$CC" -shared -o "$SYSROOT_DIR/lib/libpython${PYTAG}.so" \
        "${RUNNER_TEMP:-/tmp}/pystub_${PYTAG}_${ARCH}.c" 2>/dev/null || {
        echo "⚠️  Não foi possível compilar stub — criando .so vazio"
        touch "$SYSROOT_DIR/lib/libpython${PYTAG}.so"
    }
    rm -f "${RUNNER_TEMP:-/tmp}/pystub_${PYTAG}_${ARCH}.c"

    # _sysconfigdata_ dinâmico (sem hardcode de versão/arch).
    cat > "$SYSROOT_DIR/lib/python${PYTAG}/_sysconfigdata_.py" << PYEOF
build_time_vars = {
    'BINDIR': '/usr/bin', 'LIBDIR': '/usr/lib',
    'INCLUDEPY': '/usr/include/python${PYTAG}',
    'SO': '.so', 'EXT_SUFFIX': '.${CPTAG}-${TRIPLE}.so',
    'CC': 'clang', 'CXX': 'clang++',
    'MULTIARCH': '${TRIPLE}',
}
PYEOF
    echo "PYO3_CROSS_LIB_DIR=$SYSROOT_DIR/lib" >> "$GITHUB_ENV"
    echo "✓ Stub criado (Py ${PYTAG}, ${TRIPLE})"
}

echo "=== Baixando Python sysroot para $TRIPLE (Py ${PYTAG}) ==="
mkdir -p "$SYSROOT_DIR" "$EXTRACT_DIR"

# Cache hit (Layer 2): sysroot real já extraído não re-baixa.
FOUND_LIB=$(find "$EXTRACT_DIR" -path "*/usr/lib/libpython*.so*" -type f -print -quit 2>/dev/null || true)
LIB_DIR=""
[ -n "$FOUND_LIB" ] && LIB_DIR="$(dirname "$FOUND_LIB")"
if [ -n "$LIB_DIR" ]; then
    echo "✓ Sysroot restaurado do cache (sem re-download): $LIB_DIR"
    echo "PYO3_CROSS_LIB_DIR=$LIB_DIR"                    >> "$GITHUB_ENV"
    echo "PYO3_CROSS_PYTHON_VERSION=${PYTAG}"              >> "$GITHUB_ENV"
    echo "MATURIN_BUILD_ARGS=--target $TRIPLE --skip-auditwheel --strip -i python${PYTAG}" >> "$GITHUB_ENV"
    echo "✓ Cross-compilação configurada com sysroot em cache"
    exit 0
fi

# Tenta baixar o Python do Termux (variantes de nome).
DEB_CANDIDATES=(
  "https://packages.termux.dev/apt/termux-main/pool/main/p/python/python_${PYTAG}_${ARCH}.deb"
  "https://packages.termux.dev/apt/termux-main/pool/main/p/python/python-static_${PYTAG}_${ARCH}.deb"
)
DEB_OK=0
for URL in "${DEB_CANDIDATES[@]}"; do
    if curl -sfL -o "${SYSROOT_DIR}/python.deb" "$URL"; then
        echo "✓ Python deb baixado: $URL"
        DEB_OK=1; break
    fi
done

if [ "$DEB_OK" = "1" ]; then
    cd "$SYSROOT_DIR"
    EXTRACT_OK=0
    if command -v dpkg-deb &>/dev/null; then
        dpkg-deb -x python.deb "$EXTRACT_DIR" && EXTRACT_OK=1 || EXTRACT_OK=0
    elif command -v ar &>/dev/null; then
        ar x python.deb 2>/dev/null || true
        for f in data.tar.*; do
            [ -f "$f" ] && { tar -xf "$f" -C "$EXTRACT_DIR" 2>/dev/null && EXTRACT_OK=1 && break; }
        done
    fi
    if [ "${EXTRACT_OK:-0}" = "1" ]; then
        FOUND_LIB=$(find "$EXTRACT_DIR" -path "*/usr/lib/libpython*.so*" -type f -print -quit 2>/dev/null || true)
        LIB_DIR=""; [ -n "$FOUND_LIB" ] && LIB_DIR="$(dirname "$FOUND_LIB")"
        if [ -n "$LIB_DIR" ]; then
            echo "✓ libpython encontrado: $LIB_DIR"
            echo "PYO3_CROSS_LIB_DIR=$LIB_DIR"                 >> "$GITHUB_ENV"
            echo "PYO3_CROSS_PYTHON_VERSION=${PYTAG}"           >> "$GITHUB_ENV"
            echo "MATURIN_BUILD_ARGS=--target $TRIPLE --skip-auditwheel --strip -i python${PYTAG}" >> "$GITHUB_ENV"
            echo "✓ Cross-compilação configurada com sysroot real"
            exit 0
        fi
    fi
    echo "⚠️  Extração falhou — usando stub"
fi

create_stub
echo "PYO3_CROSS_PYTHON_VERSION=${PYTAG}" >> "$GITHUB_ENV"
echo "MATURIN_BUILD_ARGS=--target $TRIPLE --skip-auditwheel --strip -i python${PYTAG}" >> "$GITHUB_ENV"
echo "✓ Cross-compilação configurada com stub"
