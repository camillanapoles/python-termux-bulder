# Diretório de Patches por Pacote — Fábrica Universal de Wheels

O workflow **termux-wheel.yml** é agnóstico: nenhum nome de pacote/família é
hardcoded dentro do pipeline. Quando um pacote PyPI tem um sdist **incompleto**
(arquivos necessários ao build não publicados no sdist), o workflow pode chamar
um **patch** opcional, declarado **por arquivo**, sem acoplar o pipeline a
nenhuma família específica.

## Como funciona

1. O workflow extrai o sdist em `build_area/<pkg>-<ver>/`.
2. ** Só se** existir `patches/<sanitizado>.sh`, ele carrega
   `PKG_DIR` (caminho absoluto da árvore extraída) e executa o patch.
3. `<sanitizado>` = `package_name` normalizado: minúsculas, remove `.`/`+`/`_`,
   substitui caracteres não-alfanuméricos por `-`.
4. **Estratégia de lookup**: o workflow procura patch por **dois nomes**,
   em ordem, e usa o **primeiro** que existir:
   - Match exato: ex. `pydantic.core` → `pydantic-core.sh`
   - Match por prefixo (primeiro segmento antes de `-`): ex. `tree-sitter-python`
     → `tree-sitter.sh` (cobre toda a família com um único patch).
5. Patch falha o build se retornar não-zero (`set -e`).

## Por que por-arquivo (não inline no workflow)

- Mantém a auditorabilidade: o fluxo principal é reutilizável para qualquer
  módulo; casos especiais vivem isolados e versionados.
- Permite que a comunidade contribua com patches sem editar o workflow.
- O pipeline nunca "sabe" sobre tree-sitter — só que existe um patch a rodar.

## Patch de referência

| File | Cobre |
|---|---|
| `tree-sitter.sh` | Família `tree-sitter-*` (grammars): faltam `common/scanner.h`, `common/util.h`, `src/scanner.c` do sdist. Reaproveita o trecho antes inline, genérico via `PKG`, `PKG_VER` e heurística de ausência de arquivo. |

## Quando NÃO usar patch

- Build C que faltam só **dependências de sistema** (ex.: BLAS) → não cabe aqui;
  construa nativo no Termux (ver `GUIA-USO.md` §6).
- Pacote puro Python → não precisa de build.

## Adicionar um patch novo

```bash
# Sanitização (rodar localmente para descobrir o nome do arquivo):
python3 - <<'PY'
name = "Some.Package_Name"; import re
print(re.sub(r'[^a-z0-9]+','-', name.lower()).strip('-'))
PY
# saida -> some-package-name  -> criar patches/some-package-name.sh
```

O script recebe como variáveis de ambiente:
- `PKG` — package_name original (ex.: `tree-sitter-python`)
- `PKG_VER` — package_version (vazio se "latest")
- `PKG_DIR` — diretório absoluto da árvore extraída
- `ARCH`, `PYTHON_VERSION`, `TARGET`, `ANDROID_API`, `WORKSPACE`