#!/usr/bin/env bash
# Prepara um sysroot Python Android para cross-compilação com maturin.
set -euo pipefail

ARCH="${1:-aarch64}"
ANDROID_API="${2:-24}"
PYTHON_VERSION="${3:-3.12}"
SYSROOT_DIR="${SYSROOT_DIR:-${RUNNER_TEMP:-/tmp}/android-python-sysroot}"
EXTRACT_DIR="${SYSROOT_DIR}/extracted"

case "$ARCH" in
  aarch64) TRIPLE="aarch64-linux-android" ;;
  x86_64)  TRIPLE="x86_64-linux-android" ;;
  armv7l)  TRIPLE="armv7a-linux-androideabi" ;;
  i686)    TRIPLE="i686-linux-android" ;;
  *) echo "❌ Arch não suportada: $ARCH"; exit 1 ;;
esac

create_stub() {
    echo "   Criando libpython stub para linker..."
    mkdir -p "$SYSROOT_DIR/lib" "$SYSROOT_DIR/lib/python${PYTHON_VERSION}"
    NDK_BIN="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin"
    case "$ARCH" in
      aarch64) CC="${NDK_BIN}/aarch64-linux-android${ANDROID_API}-clang" ;;
      x86_64)  CC="${NDK_BIN}/x86_64-linux-android${ANDROID_API}-clang" ;;
      armv7l)  CC="${NDK_BIN}/armv7a-linux-androideabi${ANDROID_API}-clang" ;;
      i686)    CC="${NDK_BIN}/i686-linux-android${ANDROID_API}-clang" ;;
    esac
    cat > /tmp/pystub.c << 'CEOF'
int Py_IsInitialized() { return 0; }
void Py_Initialize() {}
void Py_Finalize() {}
void* PyImport_ImportModule(const char *n) { return 0; }
CEOF
    "$CC" -shared -o "$SYSROOT_DIR/lib/libpython${PYTHON_VERSION}.so" /tmp/pystub.c 2>/dev/null || {
        echo "⚠️ Não foi possível compilar stub, criando .so vazio"
        touch "$SYSROOT_DIR/lib/libpython${PYTHON_VERSION}.so"
    }
    rm -f /tmp/pystub.c

    # Sysconfig data stub
    cat > "$SYSROOT_DIR/lib/python${PYTHON_VERSION}/_sysconfigdata_.py" << 'PYEOF'
build_time_vars = {
    'BINDIR': '/usr/bin', 'LIBDIR': '/usr/lib',
    'INCLUDEPY': '/usr/include/python3.12',
    'SO': '.so', 'EXT_SUFFIX': '.cpython-312-aarch64-linux-android.so',
    'CC': 'clang', 'CXX': 'clang++',
    'MULTIARCH': 'aarch64-linux-android',
}
PYEOF
    echo "PYO3_CROSS_LIB_DIR=$SYSROOT_DIR/lib" >> "$GITHUB_ENV"
    echo "✓ Stub criado"
}

echo "=== Baixando Python sysroot para $TRIPLE ==="
mkdir -p "$SYSROOT_DIR" "$EXTRACT_DIR"

# Cache hit (Layer 2): sysroot já extraído de um run anterior — reusa sem re-download.
# Só casa um sysroot Termux real (libpython em */usr/lib/*); um stub fallback vive em $SYSROOT_DIR/lib e não dispara isto.
FOUND_LIB=$(find "$EXTRACT_DIR" -path "*/usr/lib/libpython*.so*" -type f -print -quit 2>/dev/null || true)
LIB_DIR=""
[ -n "$FOUND_LIB" ] && LIB_DIR="$(dirname "$FOUND_LIB")"
if [ -n "$LIB_DIR" ]; then
    echo "✓ Sysroot restaurado do cache (sem re-download): $LIB_DIR"
    echo "PYO3_CROSS_LIB_DIR=$LIB_DIR" >> "$GITHUB_ENV"
    echo "PYO3_CROSS_PYTHON_VERSION=${PYTHON_VERSION}" >> "$GITHUB_ENV"
    echo "MATURIN_BUILD_ARGS=--target $TRIPLE --skip-auditwheel --strip -i python${PYTHON_VERSION}" >> "$GITHUB_ENV"
    echo "✓ Cross-compilação configurada com sysroot em cache"
    exit 0
fi

# Tentar baixar Python do Termux
DEB_URL="https://packages.termux.dev/apt/termux-main/pool/main/p/python/python_${PYTHON_VERSION}_${ARCH}.deb"
if curl -sL -o "${SYSROOT_DIR}/python.deb" "$DEB_URL"; then
    echo "✓ Python deb baixado"
    cd "$SYSROOT_DIR"
    if command -v dpkg-deb &>/dev/null; then
        dpkg-deb -x python.deb "$EXTRACT_DIR" && EXTRACT_OK=1 || EXTRACT_OK=0
    elif command -v ar &>/dev/null; then
        ar x python.deb && for f in data.tar.*; do
            [ -f "$f" ] && tar -xf "$f" -C "$EXTRACT_DIR" 2>/dev/null && EXTRACT_OK=1 && break
        done || EXTRACT_OK=0
    else
        EXTRACT_OK=0
    fi
    if [ "${EXTRACT_OK:-0}" = "1" ]; then
        FOUND_LIB=$(find "$EXTRACT_DIR" -path "*/usr/lib/libpython*.so*" -type f -print -quit 2>/dev/null || true)
        LIB_DIR=""
        [ -n "$FOUND_LIB" ] && LIB_DIR="$(dirname "$FOUND_LIB")"
        if [ -n "$LIB_DIR" ]; then
            echo "✓ libpython encontrado: $LIB_DIR"
            echo "PYO3_CROSS_LIB_DIR=$LIB_DIR" >> "$GITHUB_ENV"
            echo "PYO3_CROSS_PYTHON_VERSION=${PYTHON_VERSION}" >> "$GITHUB_ENV"
            echo "MATURIN_BUILD_ARGS=--target $TRIPLE --skip-auditwheel --strip -i python${PYTHON_VERSION}" >> "$GITHUB_ENV"
            echo "✓ Cross-compilação configurada com sysroot real"
            exit 0
        fi
    fi
    echo "⚠️ Extração falhou, usando stub"
fi

create_stub
echo "PYO3_CROSS_PYTHON_VERSION=${PYTHON_VERSION}" >> "$GITHUB_ENV"
echo "MATURIN_BUILD_ARGS=--target $TRIPLE --skip-auditwheel --strip -i python${PYTHON_VERSION}" >> "$GITHUB_ENV"
echo "✓ Cross-compilação configurada com stub"
