#!/usr/bin/env bash
# Override para family tree-sitter-* (grammars).
# Antes era hardcoded no workflow; agora é um override por-família genérico:
# apenas busca arquivos faltantes no sdist (heurística por AUSÊNCIA, não por nome),
# mantendo o pipeline principal agnóstico.
#
# Recebe do workflow:
#   PKG, PKG_VER, PKG_DIR, ARCH, PYTHON_VERSION, TARGET, ANDROID_API, WORKSPACE
set -euo pipefail

cd "$PKG_DIR"

# Sanitiza versão p/ ref do git (remove pós-fixos de pre-release comuns).
TS_VER="${PKG_VER}"
TS_VER="${TS_VER%%+*}"       # +local
TS_VER="${TS_VER%%-*}"       # -rc1 (registry) só p/ lookup do ref

# Candidatos de ref a tentar, nessa ordem.
REFS=()
[ -n "$TS_VER" ] && REFS+=("v${TS_VER}" "${TS_VER}")
REFS+=("master" "main")

# Organizações upstream plausíveis para grammars tree-sitter.
ORGS=("tree-sitter" "tree-sitter-grammars")

fetch_to() {
    # fetch_to <org> <ref> <remote_relative> <local_path>
    local org="$1" ref="$2" remote="$3" local="$4"
    [ -s "$local" ] && return 0
    local content
    content=$(curl -sfL "https://raw.githubusercontent.com/${org}/${PKG}/${ref}/${remote}" 2>/dev/null || true)
    if [ -n "$content" ]; then
        mkdir -p "$(dirname "$local")"
        printf '%s' "$content" > "$local"
        echo "   override: recuperado $remote de $org/${PKG}@${ref}"
        return 0
    fi
    return 1
}

# 1) common/scanner.h (+ util.h) — grammars_multifile (typescript, php).
# Heurística por ausência: só se os .c referenciais "../../common/" mas os
# arquivos não existem.
if grep -rq '\.\./\.\./common/' --include='*.c' . 2>/dev/null \
   && [ ! -s common/scanner.h ]; then
    for HF in scanner.h util.h; do
        [ -s "common/$HF" ] && continue
        for ORG in "${ORGS[@]}"; do for REF in "${REFS[@]}"; do
            fetch_to "$ORG" "$REF" "common/$HF" "common/$HF" && break 2
        done; done
    done
fi

# 2) src/scanner.c — grammar com external scanner cujo sdist omitiu (python).
# Heurística por ausência: src/scanner.c ausente mas há referência a external_scanner.
if [ ! -f src/scanner.c ] && grep -rqE "external_scanner" --include='*.c' --include='*.h' . 2>/dev/null; then
    for ORG in "${ORGS[@]}"; do for REF in "${REFS[@]}"; do
        fetch_to "$ORG" "$REF" "src/scanner.c" "src/scanner.c" && break 2
    done; done
fi

# 3) Headers tree-sitter: PJ PURE — apenas aponta o diretório de includes.
# O workflow C/C++ detecta LANGUAGE_VERSION e escolhe o sub-diretório.
# (vendor/tree_sitter -> moderno, vendor/tree_sitter_v14 -> <=14)
# Não fazemos nada aqui: o workflow injeta o path no CFLAGS.
true
