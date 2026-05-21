# gemini

[Google Gemini CLI](https://github.com/google-gemini/gemini-cli) rodando em um
contêiner Docker `debian-slim`.

Este template é propositalmente simples: configure um workspace persistente e
uma agent home persistente, autentique o Gemini uma vez, e depois escolha se
cada run será interativo, one-shot persistente ou one-shot efêmero.

## O que este template entrega

- `Dockerfile`: Gemini CLI mais ferramentas comuns de desenvolvimento Linux.
- `compose.yml`: monta seu projeto em `/workspace` e a agent home em
  `/home/agent`.
- `setup-host.sh`: cria as pastas no host, escreve defaults seguros no `.env` e
  prepara `${AGENT_HOME_PATH}/.gemini`.

O Gemini CLI em si é instalado pelo pacote npm `@google/gemini-cli`.

## Setup

Copie o arquivo de ambiente:

```bash
install -m 0600 .env.example .env
```

Idealmente, edite estes valores para deixar o workspace e a agent home
explícitos:

```env
WORKSPACE_PATH=/path/to/workspaces/my-project
AGENT_HOME_PATH=/path/to/agent-homes/gemini
```

Se `WORKSPACE_PATH` e `AGENT_HOME_PATH` ficarem vazios, o `setup-host.sh` usa
este fallback:

```txt
~/sannux-data/workspaces/gemini
~/sannux-data/agent-homes/gemini
```

Crie as pastas no host e preencha valores faltando no `.env`:

```bash
./setup-host.sh
```

Inicie e teste a TUI uma vez:

```bash
docker compose run --rm agent
```

A partir da raiz do repositório, o mesmo fluxo é:

```bash
just setup gemini
just run gemini
```

## Cenários

### 1. Template

O template é o ambiente específico do harness: `gemini` significa Google Gemini
CLI rodando com workspace próprio e agent home isolada.

Outros templates seguem a mesma ideia para outros harnesses, como Codex, Claude,
Hermes, Pi ou opencode.

### 2. Config inicial persistente

`.env` mais `setup-host.sh` criam a primeira agent home funcional.

Autentique o Gemini com uma destas opções:

- `GEMINI_API_KEY` no `.env`;
- OAuth do Google na TUI do Gemini;
- valores de Vertex AI, como `GOOGLE_API_KEY`,
  `GOOGLE_GENAI_USE_VERTEXAI=true` e `GOOGLE_CLOUD_PROJECT`.

O Gemini guarda estado de usuário em `/home/agent/.gemini/`. Isso pode incluir
credenciais OAuth, settings, trusted folders, registro de projetos, sessões,
histórico, tokens OAuth de MCP, policies, extensions, skills, cache e outros
estados de runtime. Trate isso como privado.

### 3. Execução TUI persistente

Use isto para trabalho interativo normal:

```bash
docker compose run --rm agent
```

A partir da raiz do repositório:

```bash
just run gemini
```

Esse run fica ativo até você sair da TUI. Ele usa o workspace persistente e a
agent home persistente do `.env`.

### 4. Execução daemon persistente

Este template não fornece um serviço daemon do Gemini.

O Gemini CLI roda como TUI interativa ou como comando one-shot. Se uma versão
futura do Gemini CLI adicionar um modo daemon/server estável, adicione isso como
um serviço explícito de Compose profile e documente portas, logs e shutdown
aqui.

### 5. One-shot com home persistente

Use isto quando compartilhar a mesma agent home for aceitável:

```bash
docker compose run --rm agent -p "summarize the mounted project"
```

A partir da raiz do repositório:

```bash
just run gemini -p "summarize the mounted project"
```

O Gemini CLI informa `-p` / `--prompt` como modo headless não-interativo.

Importante: o stdin é anexado ao prompt do `-p`. Use uma única fonte de prompt
para automação normal. Combine stdin e `-p` apenas quando você quiser
intencionalmente os dois textos no mesmo pedido.

Por exemplo, este prompt somente leitura usa modo plan:

```bash
docker compose run --rm -T agent \
  --approval-mode plan \
  -p "Summarize the mounted project."
```

Para tarefas de escrita, deixe o modo de aprovação explícito. Em runs one-shot
não-interativos, não peça para o Gemini editar arquivos sem `--yolo` ou
`--approval-mode yolo`; ele pode passar bastante tempo tentando editar e só
depois informar que não tinha aprovação para continuar.

```bash
docker compose run --rm -T agent \
  --yolo \
  -p "Create /workspace/iso_date.txt with the current date in ISO 8601 format."
```

E isto envia contexto extra intencionalmente pelo stdin:

```bash
printf '%s\n' "You are running inside a Docker container." | \
  docker compose run --rm -T agent \
    --yolo \
    -p "Report the OS and create /workspace/iso_date.txt with the current date."
```

Isso é simples, mas o run pode ler e escrever o `AGENT_HOME_PATH` persistente
inteiro: auth, settings, trusted folders, sessões, cache, logs, histórico, MCP
config, policies, extensions, skills e estado de runtime.

Use `--approval-mode plan` para checks one-shot somente leitura:

```bash
docker compose run --rm -T agent \
  --approval-mode plan \
  -p "summarize the mounted project"
```

Use `--approval-mode yolo` ou `--yolo` apenas em runs onde você aceita edições e
comandos shell automáticos dentro do workspace montado.

### 6. One-shot com home efêmera

Use isto quando quiser uma `/home/agent` nova para um comando.

Com uma API key no `.env`, uma home temporária vazia já basta:

```bash
template_dir=/path/to/sannux/templates/gemini
tmp_workspace=/path/to/tmp/workspace-1
tmp_home="$(mktemp -d)"
trap 'rm -rf "$tmp_home"' EXIT

mkdir -p "$tmp_workspace"

docker compose --project-directory "$template_dir" run \
  -v "$tmp_workspace:/workspace" \
  -v "$tmp_home:/home/agent" \
  --rm -T agent \
  --yolo \
  -p "Create /workspace/test.txt with the current date in ISO 8601 format."
```

Se você depende de login OAuth, servidores MCP, extensions, skills ou outro
estado do Gemini vindo da home persistente, copie só o estado que você aceita
expor para esse run:

```bash
persistent_home=/path/to/agent-homes/gemini
test -d "$persistent_home/.gemini"
cp -R "$persistent_home/.gemini" "$tmp_home/.gemini"
```

Aviso curto: Docker `-v` pode criar pastas inexistentes no host. Crie e
inspecione as pastas você mesmo quando o caminho importar.

Outro aviso: `.gemini` pode conter auth real, trusted folders, tokens OAuth de
MCP, settings, registro de projetos, histórico, policies, extensions, skills,
cache ou outro estado privado. Copie isso apenas para runs onde você aceita
expor esse estado.

## Portas de preview

O serviço regular `agent` não publica portas fixas no host por padrão. Se o
Gemini subir um app dentro de um run, publique só a porta necessária naquele
comando:

```bash
docker compose run --rm -p 127.0.0.1:3001:3000 agent
```

Isso mapeia a porta `3001` do host para a porta `3000` do contêiner naquela
sessão. Faça o app dentro do contêiner escutar em `0.0.0.0`. Em uma VPS, exponha
`0.0.0.0:PORTA_HOST:PORTA_CONTAINER` apenas quando você realmente quiser acesso
público.

## O que vem dentro

- Base `debian trixie-slim` fixada por digest.
- Node.js 22 LTS + Gemini CLI (`@google/gemini-cli`).
- Python 3 + pip + venv, para o agente conseguir abrir tarefas em Python.
- `build-essential` para projetos com dependências nativas.
- Utilitários de CLI: `git`, `rg`, `fd`, `jq`, `fzf`, `bat`, `tree`, `less`.
- Usuário não-root `agent`, com UID/GID alinhados ao host via build args.

## O que não montar

Não monte sem pensar:

- seu diretório home real;
- chaves SSH;
- credenciais de cloud;
- tokens de gerenciadores de pacote;
- configuração global de Git ou GitHub;
- o socket do Docker.

Monte a pasta do projeto que o Gemini deve editar, e monte apenas os dados do
Gemini que você aceita expor para aquele run.

## Personalização

Edite `Dockerfile` e `compose.yml` diretamente. Adicione ferramentas que você
usa, ative flags de segurança mais rígidas (`read_only: true`, `cap_drop:
[ALL]`, `seccomp` customizado) ou troque a imagem base. Depois de mudar o
`Dockerfile`, rode:

```bash
docker compose build --no-cache
```
