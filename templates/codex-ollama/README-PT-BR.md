# codex-ollama

Codex CLI rodando em Docker, apontado para um servidor Ollama através do
endpoint `/v1` compatível com OpenAI.

Este template é propositalmente pequeno: configure uma agent home persistente,
teste uma vez na TUI e depois mude só os argumentos do Codex em cada execução.

## Example Vídeo (PT-BR 🇧🇷)

Example using `codex-ollama` (in Brazilian Portuguese).

[![Agentes de IA Seguros no Docker](https://i3.ytimg.com/vi/wqe0VU5L5aU/maxresdefault.jpg)](https://youtu.be/wqe0VU5L5aU)

- [youtu.be/wqe0VU5L5aU](https://youtu.be/wqe0VU5L5aU)

## O que este template entrega

- `Dockerfile`: Codex CLI e ferramentas comuns de desenvolvimento em Linux.
- `compose.yml`: monta seu projeto em `/workspace` e a agent home em
  `/home/agent`.
- `setup-host.sh`: cria as pastas no host e escreve
  `${AGENT_HOME_PATH}/.codex/config.toml`.
- `model_catalog.json`: metadados do modelo local do Ollama para o Codex.

O Ollama em si roda fora deste contêiner.

## Setup

Copie o arquivo de ambiente:

```bash
install -m 0600 .env.example .env
```

O ideal é editar estes valores para deixar workspace e agent home explícitos:

```env
WORKSPACE_PATH=/srv/example-data/workspaces/my-project
AGENT_HOME_PATH=/srv/example-data/agent-homes/codex-ollama
OLLAMA_BASE_URL=http://host.docker.internal:11434/v1
CODEX_MODEL=local-model:8b
```

Opcionalmente, aponte o template para seu próprio arquivo de catálogo:

```env
CODEX_MODEL_CATALOG_HOST_PATH=/srv/example-data/model-catalogs/ollama_models.json
```

Se `WORKSPACE_PATH` e `AGENT_HOME_PATH` ficarem vazios, o `setup-host.sh` usa
este fallback:

```txt
~/sannux-data/workspaces/codex-ollama
~/sannux-data/agent-homes/codex-ollama
```

Renderize a config do Codex e crie as pastas no host:

```bash
./setup-host.sh
```

Teste a TUI uma vez:

```bash
docker compose run --rm agent
```

Da raiz do repositório, o mesmo fluxo é:

```bash
just setup codex-ollama
just run codex-ollama
```

## Cenários

### 1. Template

O template é o ambiente específico do harness: `codex-ollama` significa Codex
CLI configurado para usar um endpoint Ollama.

Outros templates seguem a mesma ideia para outros harnesses, como Codex, Claude,
Gemini, Pi ou opencode.

### 2. Config inicial persistente

`.env` mais `setup-host.sh` cria a primeira agent home funcionando.

Essa home guarda config do Codex, login/API, modelo, endpoint, effort,
histórico, cache, logs e qualquer outra coisa que a CLI escrever em
`/home/agent`.

### 3. Execução TUI persistente

Use isso para o trabalho interativo normal:

```bash
docker compose run --rm agent
```

Da raiz do repositório:

```bash
just run codex-ollama
```

Isso compartilha o workspace persistente e a agent home persistente do `.env`.

### 4. Execução daemon persistente

Este template não fornece serviço daemon do Codex/Ollama.

O Codex CLI roda como TUI interativa ou como comando one-shot `codex exec`. Se
uma versão futura do Codex CLI adicionar um modo daemon/server estável, adicione
isso como um Compose profile explícito e documente aqui portas, autenticação,
logs e fluxo de parada.

### 5. Execução one-shot com home persistente

Use quando compartilhar a mesma agent home for aceitável:

```bash
printf '%s\n' "Resuma este projeto." | \
  docker compose run --rm -T agent exec - --ephemeral --yolo
```

É simples, mas a execução pode ler e escrever a `AGENT_HOME_PATH` inteira:
config, autenticação, cache, logs, histórico, memória e estado de runtime.

### 6. Execução one-shot com home efêmera

Use quando você quiser uma `/home/agent` nova para um comando, reaproveitando só
a pasta de config do Codex que já foi testada:

```bash
persistent_home=/srv/example-data/agent-homes/codex-ollama
tmp_workspace=/srv/example-data/tmp/workspace-1
tmp_home=/srv/example-data/tmp/home-1

mkdir -p "$tmp_workspace" "$tmp_home"
test -d "$persistent_home/.codex"

printf '%s\n' "Resuma este workspace temporário." | \
  docker compose run \
    -v "$tmp_workspace:/workspace" \
    -v "$tmp_home:/home/agent" \
    -v "$persistent_home/.codex:/home/agent/.codex" \
    --rm -T agent exec - --ephemeral --yolo
```

Aviso curto: Docker `-v` pode criar pastas ausentes no host. Crie e confira as
pastas você mesmo quando o caminho importar.

Outro aviso: isso expõe tudo que existir dentro de `.codex`. Pode incluir API
keys, autenticação, config, memórias ou outros dados do Codex. A ideia não é
"nenhum dado sensível"; é "só o mínimo que você aceita expor para este run".

## Portas de preview

Se o agente subir um app dentro do contêiner, publique só a porta necessária
para aquele run:

```bash
docker compose run --rm -p 127.0.0.1:3001:3000 agent
```

Faça o app escutar em `0.0.0.0` dentro do contêiner. Em uma VPS, exponha
`0.0.0.0:PORTA_HOST:PORTA_CONTAINER` só quando você realmente quiser acesso
público.

## Catálogo de modelos

O Codex precisa de metadados para nomes de modelos locais do Ollama. Este
template inclui um catálogo padrão pequeno e monta um arquivo de catálogo como
somente leitura:

```txt
${CODEX_MODEL_CATALOG_HOST_PATH:-./model_catalog.json} -> ${CODEX_MODEL_CATALOG_PATH:-/opt/sannux/model_catalog.json}
```

Deixe `CODEX_MODEL_CATALOG_HOST_PATH` vazio para usar o `./model_catalog.json`
versionado. Defina esse valor com um caminho absoluto do host quando o catálogo
for pessoal ou específico da máquina:

```env
CODEX_MODEL_CATALOG_HOST_PATH=/srv/example-data/model-catalogs/ollama_models.json
CODEX_MODEL_CATALOG_PATH=/opt/sannux/model_catalog.json
```

`CODEX_MODEL_CATALOG_PATH` é o caminho dentro do contêiner escrito na config do
Codex. Não coloque o caminho do host nele. O Compose usa
`create_host_path: false`, então um catálogo customizado ausente falha em vez de
ser criado silenciosamente.

Se você mudar `CODEX_MODEL`, mantenha o catálogo selecionado alinhado.

## Modelo de permissão

A config gerada do Codex usa:

```toml
approval_policy = "never"
sandbox_mode = "danger-full-access"
```

Isso é intencional aqui: o Docker é a fronteira do sandbox. O agente consegue
ver o workspace montado, a agent home montada, o catálogo de modelos
somente-leitura e a rede.

## O que não montar

Não monte casualmente:

- sua home real;
- chaves SSH;
- credenciais de cloud;
- tokens de gerenciadores de pacotes;
- configuração global do Git ou GitHub;
- o socket do Docker.

Monte a pasta do projeto que o agente deve editar, e monte apenas os dados do
agente que você aceita expor para aquele run.

## Personalizar

Edite `Dockerfile`, `compose.yml` ou `codex-config.toml.template` diretamente.
Para metadados pessoais de modelo, prefira `CODEX_MODEL_CATALOG_HOST_PATH` em
vez de editar o `model_catalog.json` versionado. Depois de alterar a imagem:

```bash
docker compose build --no-cache
```
