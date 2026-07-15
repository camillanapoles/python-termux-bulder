# Guia de Uso Agnóstico — Wheels Python para Android/Termux

Como construir e instalar **qualquer** pacote Python no Termux, decidindo a
estratégia correta por tipo de pacote. Workflow único:
`.github/workflows/android-wheel.yml` (repo `camillanapoles/python-termux-bulder`).

---

## 1. Árvore de decisão — qual estratégia usar?

```
Pacote PyPI
  ├── Tem wheel py3-none-any no PyPI?         → puro-Python
  │                                              → pip install <pkg> DIRETO (não precisa do workflow)
  ├── Tem extensão Rust (PyO3/maturin)?       → Workflow (branch Cargo.toml → maturin)
  ├── Tem extensão C/C++/Cython?              → Workflow (branch pyproject/setup.py → cross-compile NDK)
  ├── Precisa de BLAS/LAPACK (numpy, scipy)?  → Build NATIVO no Termux (pip install compila com openblas)
  └── Tem wheel manylinux aarch64 e "funciona"? → às vezes pip instala direto; se falhar, use o Workflow
```

**Como descobrir o tipo**: `pip index versions <pkg>` e olhe o nome do wheel no PyPI.
- `*-py3-none-any.whl` = puro-Python → instala direto.
- `*-cp3XX-cp3XX-linux_aarch64.whl` (manylinux) = nativo → o Termux **rejeita** (bionic ≠ glibc) → precisa do Workflow.
- `*-cp3XX-abi3-*` = ABI estável → geralmente instala direto no Termux.

---

## 2. Regra de ouro: **pip, NÃO uv**

No Termux:
- **pip ACEITA** wheels `linux_aarch64` (o Python do Termux reporta `sysconfig.get_platform() = linux-aarch64`).
- **uv REJEITA** qualquer wheel `linux_*` — ele detecta o Termux como `android_24_arm64_v8a` e recusa (mesmo manylinux).

```bash
# CERTO
pip install pacote-...-linux_aarch64.whl

# ERRADO (vai tentar compilar do sdist e falhar)
uv tool install pacote
```

> Se insistir em uv, force a plataforma: `uv pip install --python-platform x ...` — mas o caminho nativo é **pip**.

---

## 3. Versão do Python — coordene!

O workflow recebe `python_version` (ex.: `3.12`). O wheel sai com o tag dessa versão
(`cp312`) **exceto** pacotes com ABI estável (`abi3`, que servem para qualquer Python ≥3.9).

- Descubra seu Python no Termux: `python3 --version` (ou `python --version`).
- Passe a **mesma versão** para o workflow: `-f python_version=3.12`.
- Pacotes `cp3XX` (ex.: `rapidfuzz`, `tree-sitter` core) só servem para aquela versão exata.
- Pacotes `abi3` (ex.: todos os `tree-sitter-*` grammars) são portáveis entre versões.

> Dica: escolha **uma** versão e use-a para todo o conjunto de wheels.

---

## 4. Fluxo padrão — construir e instalar qualquer pacote

```bash
# 1. Disparar o build no GitHub Actions
gh workflow run android-wheel.yml \
  -f package_name=<pacote> \
  -f package_version=<versao-ou-vazio> \
  -f python_version=3.12 \
  -f arch=aarch64

# 2. Aguardar concluir (mostra progresso)
gh run watch

# 3. Baixar o artefato (ID do run aparece em `gh run list`)
gh run download <run-id> -n <pacote>-android-aarch64 \
  -R camillanapoles/python-termux-bulder

# 4. Instalar no Termux
pip install <pacote>-*-linux_aarch64.whl
```

**Arquiteturas**: `aarch64` (padrão, maioria dos celulares), `x86_64`, `armv7l`, `i686`.

---

## 5. O que o workflow faz automaticamente (você não precisa configurar)

O workflow **detecta o tipo de projeto** e escolhe a ferramenta:

| Detecção | Ferramenta | Cross-compile Android? |
|---|---|---|
| `Cargo.toml` | maturin (Rust) | ✅ via `CARGO_TARGET_*` + sysroot + fake-libpython |
| `pyproject.toml` | `python -m build` (C/C++/Cython) | ✅ via `CC/CXX/LDSHARED` → NDK clang + `_PYTHON_HOST_PLATFORM` |
| `setup.py` | `pip wheel` (C/C++ legado) | ✅ idem |

Truques já embutidos (mesma estratégia para Rust e C/C++):
- **Fake libpython**: stub `libpython3.XX.so` + `-Wl,--unresolved-symbols=ignore-all` (símbolos resolvidos em runtime pelo Python do Termux).
- **`_PYTHON_HOST_PLATFORM=linux-<arch>`**: o wheel sai com tag `linux_<arch>` (não manylinux, não x86_64).
- **`-include stdbool.h`**: corrige parsers C gerados que esquecem `<stdbool.h>` (tree-sitter).
- **Headers tree-sitter vendorizados** + seleção por `LANGUAGE_VERSION` + auto-fetch de `common/` do GitHub — grammars com sdist incompleto compilam.

---

## 6. Casos especiais

### numpy / scipy / pacotes com BLAS-LAPACK
**NÃO use o workflow** — cross-compile com meson + BLAS Android é impraticável.
No Termux, instale **nativamente** (o Termux tem openblas):
```bash
pkg install libopenblas                    # se faltar
NPY_USE_BLAS=1 pip install numpy           # compila nativamente (~5-15 min)
# ou, se disponível no Termux:
pkg install python-numpy
```

### tree-sitter-<linguagem> (grammars)
Funcionam pelo Workflow com tag `abi3` (portáveis). O workflow cuida dos headers
automaticamente. Basta o fluxo padrão (seção 4).

### Pacote só tem wheel manylinux (nenhum sdist)
O workflow faz `pip download --no-binary :all:` (força sdist). Se o pacote **não
publica sdist**, o build falha — nesse caso não há como cross-compilar; use a wheel
manylinux direto (pode funcionar com `patchelf`) ou construa nativo no Termux.

---

## 7. Compatibilidade testada (build via workflow → pip install → funcional)

| Pacote | Tipo | Resultado |
|---|---|---|
| `graphifyy` | puro-Python | ✅ `py3-none-any`, `import graphify` OK |
| `rapidfuzz` | C++ (Cython) | ✅ `linux_aarch64`, `fuzz.ratio()` funcional |
| `tree-sitter` (core) | C | ✅ `linux_aarch64` |
| `tree-sitter-python`, `-c`, `-cpp`, `-rust`, `-go`, `-java`, `-javascript`, `-typescript`, `-php`, `-ruby`, `-bash`, `-json`, `-lua`, `-swift`, `-kotlin`, `-scala`, `-c-sharp`, `-powershell`, `-elixir`, `-objc`, `-julia`, `-verilog`, `-fortran`, `-groovy`, `-zig` | C (grammar, `abi3`) | ✅ todos `linux_aarch64` |
| `numpy` | C + BLAS (meson) | ❌ via workflow → **nativo no Termux** (`pkg`/pip) |

---

## 8. Troubleshooting

| Sintoma | Causa / Solução |
|---|---|
| `uv: incompatible with the current platform (android)` | Use **pip**, não uv (seção 2). |
| `unable to find library -lpython` | Interno do workflow (fake-lib); se aparecer num build seu, o pacote linka libpython explicitamente — já coberto pela estratégia. |
| `tree_sitter/parser.h not found` | Já auto-resolvido pelo workflow (vendor). |
| Wheel sai `linux_x86_64` | Versão antiga do workflow; faça `git pull` — a branch C/C++ agora cross-compila. |
| `cp314` vs `cp312` mismatch | Coordene `python_version` (seção 3) — rebuild com a versão do seu Python. |
| numpy/scipy não buildam no workflow | Esperado (BLAS); use build nativo no Termux (seção 6). |

---

## 9. Resumo em uma linha

> **Puro-Python → `pip install` direto. Nativo (Rust/C/C++) → Workflow (`gh workflow run`) → baixa wheel `linux_aarch64` → `pip install`. numpy/BLAS → nativo no Termux. Sempre `pip`, nunca `uv`.**
