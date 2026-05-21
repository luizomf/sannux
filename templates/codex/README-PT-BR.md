# codex

OpenAI Codex CLI rodando em Docker.

Este template é intencionalmente pequeno: configure uma agent home persistente,
teste uma vez na TUI, depois mude apenas os argumentos do Codex em cada run.

## O que este template entrega

- `Dockerfile`: Codex CLI mais ferramentas comuns de desenvolvimento Linux.
- `compose.yml`: monta seu projeto em `/workspace` e a agent home em
  `/home/agent`.
- `setup-host.sh`: cria as pastas no host e escreve defaults seguros no `.env`.

## Setup

Copie o arquivo de ambiente:

```bash
install -m 0600 .env.example .env
```

Idealmente, edite estes valores para deixar workspace e agent home explícitos:

```env
WORKSPACE_PATH=/srv/example-data/workspaces/my-project
AGENT_HOME_PATH=/srv/example-data/agent-homes/codex
```

Se você usa OpenAI API key em vez de login OAuth, defina também:

```env
OPENAI_API_KEY=sk-...
```

Mantenha `.env` privado. Ele é carregado só pelo serviço Compose deste template,
mas a chave continua sendo uma credencial real.

Se `WORKSPACE_PATH` e `AGENT_HOME_PATH` ficarem vazios, o `setup-host.sh` usa
este fallback:

```txt
~/sannux-data/workspaces/codex
~/sannux-data/agent-homes/codex
```

Crie as pastas no host e preencha valores ausentes do `.env`:

```bash
./setup-host.sh
```

Teste a TUI uma vez:

```bash
docker compose run --rm agent
```

A partir da raiz do repositório, o mesmo fluxo é:

```bash
just setup codex
just run codex
```

Escolha um caminho de auth:

- API key: defina `OPENAI_API_KEY` no `.env`, depois rode a TUI ou os comandos
  one-shot normalmente. Não precisa fazer login no Codex. Se você não definir
  antes, o prompt do Codex também pode pedir a API key dentro do contêiner.
- Login OAuth/subscription: deixe `OPENAI_API_KEY` vazio e deixe o Codex pedir
  login na primeira execução da TUI. Dentro do Docker, escolha **Sign in with
  Device Code**. Não escolha **Sign in with ChatGPT** no contêiner: esse caminho
  assume um browser desktop local e não combina com esta imagem Docker.
- Login OAuth/subscription sem interface: rode isto uma vez em uma máquina sem
  browser:

```bash
docker compose run --rm agent login --device-auth
```

Os tokens OAuth vão para `${AGENT_HOME_PATH}/.codex/auth.json` no host, então
chamadas seguintes de `docker compose run --rm agent` pulam a autenticação.

## Cenários

### 1. Template

O template é o ambiente específico do harness: `codex` significa OpenAI Codex
CLI com o fluxo normal de auth e config da OpenAI.

Outros templates seguem a mesma ideia para outros harnesses ou providers, como
`codex-ollama`, `claude-ollama`, Gemini, Pi ou opencode.

### 2. Config inicial persistente

`.env` mais `setup-host.sh` cria a primeira agent home funcionando.

Para este harness, a auth do provider vem de `OPENAI_API_KEY` no `.env` ou do
estado de login OAuth em `.codex`. Quem usa API key pode rodar sem nenhuma auth
pré-configurada em `.codex`. Quem usa OAuth deve preservar a agent home
persistente para o estado de login.

A agent home também pode guardar config, sessões, logs, cache, memória,
histórico de shell, config de MCP, plugins e outros estados de runtime em
`/home/agent`.

### 3. Execução TUI persistente

Use isto para trabalho interativo normal:

```bash
docker compose run --rm agent
```

A partir da raiz do repositório:

```bash
just run codex
```

Isso compartilha o workspace persistente e a agent home persistente do `.env`.

Para abrir um shell interativo em vez do agente:

```bash
docker compose run --rm --entrypoint bash agent
```

### 4. Execução daemon persistente

Este template não fornece serviço daemon do Codex.

O Codex CLI roda como TUI interativa ou como comando one-shot `codex exec`. Se
uma versão futura do Codex CLI adicionar um modo daemon/server estável, adicione
isso como um Compose profile explícito e documente aqui portas, autenticação,
logs e fluxo de parada.

### 5. Execução one-shot com home persistente

Use isto quando compartilhar a mesma agent home for aceitável:

```bash
printf '%s\n' "Summarize this project." | \
  docker compose run --rm -T agent exec \
    --ephemeral --dangerously-bypass-approvals-and-sandbox -
```

Isso é simples, mas o run pode ler e escrever no `AGENT_HOME_PATH` persistente
inteiro: config, auth, cache, logs, histórico, memória, config de MCP, plugins e
estado de runtime. `--ephemeral` diz ao Codex para não persistir aquela sessão
do `exec`.

Você também pode sobrescrever o workspace para um comando:

```bash
tmp_workspace=/srv/example-data/tmp/workspace-1
mkdir -p "$tmp_workspace"

printf '%s\n' "Summarize this temporary workspace." | \
  docker compose run \
    -v "$tmp_workspace:/workspace" \
    --rm -T agent exec \
    --ephemeral --dangerously-bypass-approvals-and-sandbox -
```

Isso ainda usa a agent home persistente do `.env`; só `/workspace` é
sobrescrito para aquele comando.

### 6. Execução one-shot com home efêmera

No Codex, uma home efêmera útil ainda precisa do diretório `.codex` já testado.
Esse diretório carrega login/auth, config e qualquer estado do Codex que você
aceita expor para este run. O restante de `/home/agent` fica temporário.

```bash
template_dir=/srv/example/templates/codex
tmp_workspace=/srv/example-data/tmp/workspace-1
persistent_home=/srv/example-data/agent-homes/codex
tmp_home="$(mktemp -d)"
trap 'rm -rf "$tmp_home"' EXIT

mkdir -p "$tmp_workspace"
test -d "$persistent_home/.codex"

printf '%s\n' "Summarize this temporary workspace." | \
  docker compose --project-directory "$template_dir" run \
    -v "$tmp_workspace:/workspace" \
    -v "$tmp_home:/home/agent" \
    -v "$persistent_home/.codex:/home/agent/.codex" \
    --rm -T agent exec \
    --ephemeral --dangerously-bypass-approvals-and-sandbox -
```

Aviso curto: Docker `-v` pode criar pastas ausentes no host. Crie e inspecione
as pastas você mesmo quando o caminho importar.

Isso expõe tudo dentro de `.codex`. Pode incluir API keys, auth state, config,
memórias ou outros dados do Codex. A ideia não é "sem sensível"; é "só o mínimo
que você aceita expor para este run."

Se você usa apenas `OPENAI_API_KEY` pelo `.env` e não precisa de nenhuma config
do Codex, pode omitir o mount de `.codex`. A maioria dos usuários deve manter,
porque login OAuth e config da CLI vivem ali.

## Portas de preview

Se o agente subir um app dentro do contêiner, publique só a porta necessária
naquele run:

```bash
docker compose run --rm -p 127.0.0.1:3001:3000 agent
```

Faça o app escutar em `0.0.0.0` dentro do contêiner. Em uma VPS, exponha
`0.0.0.0:PORTA_HOST:PORTA_CONTAINER` só quando realmente quiser acesso público.

## Modelo de permissão

Os exemplos one-shot usam:

```bash
--dangerously-bypass-approvals-and-sandbox
```

Isso é intencional aqui: o Docker é a fronteira do sandbox para esses comandos.
O agente consegue ver o workspace montado, a agent home montada e a rede.

Para trabalho interativo na TUI, escolha o modo de permissão que quiser dentro
do Codex.

## O que não montar

Não monte casualmente:

- sua home real;
- chaves SSH;
- credenciais de cloud;
- tokens de gerenciadores de pacote;
- config global do Git ou GitHub;
- o socket do Docker.

Monte a pasta do projeto que o agente deve editar, e monte apenas os dados de
agente que você aceita expor para aquele run.

## O que tem dentro

- Base Debian trixie-slim fixada por digest.
- Node.js 22 LTS + Codex CLI (`@openai/codex`).
- Python 3 + pip + venv.
- `build-essential` para projetos com dependências nativas.
- Ferramentas de CLI: `git`, `rg`, `fd`, `jq`, `fzf`, `bat`, `tree`, `less`.
- Usuário não-root `agent`, com UID/GID igualados ao seu host via build args.

## O que é montado

- `${WORKSPACE_PATH}` (host) -> `/workspace` (contêiner): seu projeto.
- `${AGENT_HOME_PATH}` (host) -> `/home/agent` (contêiner): estado do Codex.

Os dois caminhos devem ficar fora do checkout do `sannux`. Os bind mounts do
Compose usam `create_host_path: false`, então pastas ausentes falham cedo em vez
de serem criadas no lugar errado.

## Limites de recursos

`MEM_LIMIT`, `CPU_LIMIT` e `pids_limit` são limites de recurso, não segurança.
Ajuste ao tamanho da sua VPS ou da alocação do Docker Desktop.

## Personalizar

Edite `Dockerfile` e `compose.yml` diretamente. Adicione as ferramentas que
você usa, ajuste a config do Codex na agent home, ou aperte as opções do Compose
para seu deploy. Depois de alterar a imagem:

```bash
docker compose build --no-cache
```
