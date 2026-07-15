# 🏭 Android Wheel Factory

Uma fábrica automatizada para compilar pacotes Python com extensões Rust (usando Maturin/PyO3) para Android ARM64 (Termux).

## 🎯 Objetivo

Este repositório fornece um workflow do GitHub Actions que compila wheels Python para Android/Termux nas arquiteturas `aarch64`, `x86_64`, `armv7l` e `i686`, permitindo a instalação de pacotes com extensões nativas no Termux.

## 🔧 Como Funciona

### Desafio Técnico

Ao compilar extensões Python/Rust para Android usando cross-compilation, enfrentamos um problema clássico:
- O linker procura por `libpython3.XX.so` compilada para Android ARM64
- Esta biblioteca não existe no ambiente Ubuntu do GitHub Actions
- O linker falha com: `ld.lld: error: unable to find library -lpython3.12`

### Solução: Fake Library Strategy

Implementamos uma estratégia elegante que "engana" o linker:

1. **Criamos uma biblioteca falsa (stub)**: Um arquivo vazio `libpython3.XX.so`
2. **Configuramos RUSTFLAGS para**:
   - Adicionar o diretório da biblioteca falsa ao search path (`-L`)
   - Ignorar símbolos não resolvidos durante a linkagem
3. **Resultado**: O build termina com sucesso, e os símbolos Python são resolvidos em **runtime** pelo Termux

### Variáveis de Ambiente Críticas

```yaml
env:
  PYO3_NO_PYTHON_LINKING: 1  # Evita linkagem dinâmica com libpython
  RUSTFLAGS: "-L fake_libs -C link-arg=-Wl,--unresolved-symbols=ignore-all -C link-arg=-Wl,--allow-shlib-undefined"
```

## 🚀 Uso

### 1. Disparar o Workflow Manualmente

No GitHub, vá até **Actions** → **Android Wheel Factory** → **Run workflow**

Preencha os parâmetros:
- **package_name**: Nome do pacote PyPI (ex: `jiter`, `pydantic-core`, `orjson`)
- **package_version**: Versão específica (ex: `0.12.0`) — deixe em branco para a mais recente
- **python_version**: Versão do Python no Termux (ex: `3.12`)
- **arch**: Arquitetura alvo — `aarch64` (padrão), `x86_64`, `armv7l`, `i686`

### 2. Baixar o Wheel Compilado

Após o build bem-sucedido, o wheel estará disponível em **Artifacts**.
Também via CLI local (`gh` autenticado):

```bash
gh workflow run android-wheel.yml -f package_name=jiter -f python_version=3.12 -f arch=aarch64
gh run watch
gh run download <run-id> -n jiter-android-aarch64
```

> Fluxo completo, contrato de I/O, leis da infraestrutura e estratégia de checkpoint de cache em [`SEQUENCIADOR.md`](SEQUENCIADOR.md).

### 3. Instalar no Termux

```bash
# Transferir o wheel para o dispositivo Android
# Depois, no Termux:
pip install nome_do_pacote-versao-cp312-cp312-linux_aarch64.whl
```

## 📋 Requisitos

- GitHub Actions com runners `ubuntu-latest`
- Android NDK (já disponível no GitHub Actions)
- Python 3.x
- Rust toolchain com suporte a `aarch64-linux-android`
- Maturin (instalado automaticamente)

## 🛠️ Estrutura do Workflow

```yaml
steps:
  1. Checkout do repositório
  2. Setup Python com cache
  3. Cache do Rust toolchain e dependências
  4. Setup Rust + NDK + Fake libpython
  5. Download do código-fonte do pacote
  6. Build com Maturin (cross-compilation)
  7. Upload do wheel como artefato
```

## 🎨 Otimizações Implementadas

### Performance
- ✅ Cache de dependências Pip
- ✅ Cache agressivo do Rust (toolchain + registry + builds)
- ✅ Cache com keys específicas para Android target
- ✅ Build com `--strip` para reduzir tamanho do binário

### Robustez
- ✅ `set -e` para falhar rapidamente em erros
- ✅ Validação de artefatos com `if-no-files-found: error`
- ✅ Logs detalhados em cada etapa
- ✅ Emojis para facilitar leitura dos logs

### Segurança
- ✅ Minimal permissions (`contents: read`)
- ✅ Versões fixas das actions (@v4, @v5)
- ✅ Uso de variáveis de ambiente do GitHub (não hardcoded)

## 📚 Referências Técnicas

### Flags RUSTFLAGS Explicadas

```bash
-L ${{ github.workspace }}/fake_libs
# Adiciona o diretório fake_libs ao library search path

-C link-arg=-Wl,--unresolved-symbols=ignore-all
# Instrui o linker a ignorar símbolos não resolvidos
# Essencial para a estratégia de fake library

-C link-arg=-Wl,--allow-shlib-undefined
# Permite undefined symbols em shared libraries
# Símbolos serão resolvidos pelo Python do Termux em runtime
```

### Por que `PYO3_NO_PYTHON_LINKING=1`?

PyO3 (framework Rust/Python) tem dois modos de linkagem:
- **Dynamic**: Linka com `libpython.so` (padrão no Linux)
- **Static/Embedding**: Não linka, símbolos resolvidos externamente

Para Android, usamos o modo embedding, pois o Termux fornecerá o Python em runtime.

### Por que `--skip-auditwheel`?

`auditwheel` é uma ferramenta que verifica compatibilidade de wheels Linux:
- Valida se bibliotecas dinâmicas estão incluídas
- Renomeia para seguir PEP 600 (manylinux)

Para Android:
- ❌ Não é um sistema manylinux padrão
- ❌ Bibliotecas serão fornecidas pelo Termux
- ✅ Pulamos a verificação com `--skip-auditwheel`

## 🧪 Pacotes Testados

- ✅ `jiter` (Fast JSON iterator)
- ✅ `pydantic-core` (Validação de dados Pydantic)
- ⏳ Adicione mais aqui conforme testar

## 🤝 Contribuindo

Pull requests são bem-vindos! Especialmente para:
- Adicionar suporte a outros targets Android (x86_64, armv7)
- Otimizar cache e build time
- Testar novos pacotes PyPI
- Melhorar documentação

## 📄 Licença

Este projeto é fornecido "como está", sem garantias. Use por sua conta e risco.

## 🐛 Troubleshooting

### Erro: "Couldn't find any python interpreters"
**Solução**: Sempre use `--interpreter python3.XX` no maturin build

### Erro: "unable to find library -lpython3.XX"
**Solução**: Verifique se a fake library foi criada e RUSTFLAGS está configurada

### Erro: "symbol not found" no Termux
**Causa**: Versão do Python no Termux diferente da usada no build
**Solução**: Use a mesma versão Python no workflow e no Termux

## 🌟 Agradecimentos

- PyO3 team pela excelente framework Rust/Python
- Maturin pela ferramenta de build
- Termux pela possibilidade de rodar Python no Android
- GitHub Actions pela infraestrutura de CI/CD gratuita

---

**Made with 💜 for the Termux community**
