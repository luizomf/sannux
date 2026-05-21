# claude-code

Claude Code rodando em Docker com autenticação da Anthropic. Ele suporta
execuções TUI interativas, execuções one-shot e um daemon opcional de Remote
Control.

Este template é intencionalmente simples: configure um workspace persistente e
uma agent home persistente, teste a TUI uma vez, e depois escolha se cada run é
interativa, daemonizada, one-shot persistente ou one-shot efêmera.

## O que este template entrega

- `Dockerfile`: Claude Code mais ferramentas comuns de desenvolvimento Linux.
- `compose.yml`: monta seu projeto em `/workspace` e a agent home em
  `/home/agent`.
- `setup-host.sh`: cria as pastas no host, escreve defaults seguros no `.env` e
  prepara os arquivos de estado do Claude.
- `remote-control`: serviço daemon opcional para Claude Code Remote Control.

## Setup

Copie o arquivo de ambiente:

```bash
install -m 0600 .env.example .env
```

Idealmente, edite estes valores para deixar workspace e agent home explícitos:

```env
WORKSPACE_PATH=/path/to/workspaces/my-project
AGENT_HOME_PATH=/path/to/agent-homes/claude-code
```

Se `WORKSPACE_PATH` e `AGENT_HOME_PATH` ficarem vazios, o `setup-host.sh` usa
este fallback:

```txt
~/sannux-data/workspaces/claude-code
~/sannux-data/agent-homes/claude-code
```

Crie as pastas no host e preencha valores ausentes no `.env`:

```bash
./setup-host.sh
```

Inicie e teste a TUI uma vez:

```bash
docker compose run --rm agent
```

Da raiz do repositório, o mesmo fluxo é:

```bash
just setup claude-code
just run claude-code
```

## Cenários

### 1. Template

O template é o ambiente específico do harness: `claude-code` significa Claude
Code configurado para uso real com Anthropic/Claude Code.

Outros templates seguem a mesma ideia para outros harnesses, como Codex, Claude
com Ollama, Gemini, Pi ou opencode.

### 2. Config inicial persistente

`.env` mais `setup-host.sh` cria a primeira agent home funcional.

Para runs normais do Claude Code, autentique com `ANTHROPIC_API_KEY` no `.env`
ou pelo fluxo de login do Claude Code dentro do contêiner. O estado de login e
configuração fica no `AGENT_HOME_PATH` persistente, não na sua home real do
host.

O Claude Code guarda estado importante de usuário em `/home/agent/.claude/` e
`/home/agent/.claude.json`: auth, settings, projetos confiáveis, sessões, config
de MCP, hooks, cache e outros estados de runtime. Trate os dois caminhos como
privados.

Remote Control é um fluxo daemon real do Claude Code. Use autenticação
Anthropic real do Claude Code na home persistente para ele; um `.env` com
placeholders no estilo Ollama não basta.

### 3. Execução TUI persistente

Use isto para trabalho interativo normal:

```bash
docker compose run --rm agent
```

Da raiz do repositório:

```bash
just run claude-code
```

Esta run fica ativa até você sair da TUI. Ela usa o workspace persistente e a
agent home persistente do `.env`.

### 4. Execução daemon persistente

Use isto quando quiser deixar o Claude Code Remote Control rodando em segundo
plano:

```bash
docker compose --profile daemon up -d remote-control
docker compose logs -f remote-control
docker compose stop remote-control
```

Da raiz do repositório:

```bash
just up claude-code remote-control
just logs claude-code remote-control
just ps claude-code
just down claude-code
```

O daemon executa:

```bash
claude -n main-session --remote-control
```

Ele usa o mesmo `WORKSPACE_PATH` e `AGENT_HOME_PATH` persistentes da TUI. Mude
o workspace alterando `WORKSPACE_PATH` no `.env` antes de iniciar o daemon, ou
sobrescrevendo essa variável do Compose naquele start. Mantenha a agent home
igual, a menos que você queira intencionalmente outra identidade do Claude.

Trate a URL do Remote Control como segredo. Qualquer pessoa com acesso a essa
sessão consegue controlar o Claude Code dentro do workspace montado.

### 5. Execução one-shot com home persistente

Use isto quando compartilhar a mesma agent home for aceitável:

```bash
printf '%s\n' "Resuma este projeto." | \
  docker compose run --rm -T agent \
    --dangerously-skip-permissions --no-session-persistence -p -
```

É simples, mas a execução pode ler e escrever a `AGENT_HOME_PATH` inteira:
auth, settings, sessões, cache, logs, histórico, plugins, config de MCP, hooks,
projetos confiáveis e estado de runtime. `--no-session-persistence` diz ao
Claude Code para não salvar aquela conversa.

Você também pode trocar o workspace para um comando:

```bash
test -d "$HOME/Projects/example-project"
echo "Just a test. Create a file called test.txt in the current directory. Add the current timestamp inside it in ISO 8601/RFC 3339 format, including timezone." | \
  docker compose run \
    -v "$HOME/Projects/example-project:/workspace" \
    --rm -T agent \
    --dangerously-skip-permissions \
    --no-session-persistence \
    -p -
```

Isso ainda usa a agent home persistente do `.env`; apenas `/workspace` é
sobrescrito para aquele comando.

### 6. Execução one-shot com home efêmera

Use isto quando você quiser uma `/home/agent` nova para um comando,
reaproveitando os arquivos de estado do Claude da home persistente:

```bash
template_dir=/path/to/sannux/templates/claude-code
tmp_workspace=/path/to/sandbox/tmp/workspace-1
persistent_home=/path/to/agent-homes/claude-code
tmp_home="$(mktemp -d)"
trap 'rm -rf "$tmp_home"' EXIT

mkdir -p "$tmp_workspace"
test -d "$persistent_home/.claude"
test -f "$persistent_home/.claude.json"
cp -R "$persistent_home/.claude" "$tmp_home/.claude"
cp -p "$persistent_home/.claude.json" "$tmp_home/.claude.json"

printf '%s\n' "Resuma este workspace temporário." | \
  docker compose --project-directory "$template_dir" run \
    -v "$tmp_workspace:/workspace" \
    -v "$tmp_home:/home/agent" \
    --rm -T agent \
    --dangerously-skip-permissions --no-session-persistence -p -
```

Aviso curto: Docker `-v` pode criar pastas ausentes no host. Crie e confira as
pastas você mesmo quando o caminho importar.

No Claude Code, a pasta `.claude` e o arquivo `.claude.json` copiados podem
conter auth real, settings, projetos confiáveis, config de MCP, hooks e cache.
Copie esses caminhos apenas para runs onde você aceita expor esse estado.

## Portas de preview

O serviço `agent` comum não publica portas fixas no host por padrão. Se o
Claude Code subir um app dentro de uma run, publique só a porta necessária
naquele comando:

```bash
docker compose run --rm -p 127.0.0.1:3001:3000 agent
```

Isso mapeia a porta `3001` do host para a porta `3000` do contêiner naquela
sessão. Faça o app dentro do contêiner escutar em `0.0.0.0`.

O daemon `remote-control` publica os valores configurados em `HOST_PORT_*`
porque ele é um endpoint remoto persistente. Em uma VPS, configure
`PORT_BIND_ADDRESS=0.0.0.0` apenas quando você realmente quiser expor essas
portas.

## Modelo de permissão

A TUI e o daemon usam o comportamento normal de permissões do Claude Code. Os
exemplos one-shot usam:

```bash
--dangerously-skip-permissions
```

Essa é uma escolha por comando para runs sem supervisão, onde o Docker é a
fronteira de sandbox. O agente consegue ver o workspace montado, a agent home
montada e a rede.

## O que não montar

Não monte casualmente:

- sua home real;
- chaves SSH;
- credenciais de cloud;
- tokens de gerenciadores de pacote;
- config global de Git ou GitHub;
- o socket do Docker.

Monte a pasta do projeto que o Claude Code deve editar, e monte apenas o estado
do Claude que você aceita expor para aquela run.

## O que tem dentro

- Base Debian trixie-slim fixada por digest.
- Node.js 22 LTS + Claude Code (`@anthropic-ai/claude-code`).
- Python 3 + pip + venv.
- `build-essential` para projetos com dependências nativas.
- Utilitários de CLI: `git`, `rg`, `fd`, `jq`, `fzf`, `bat`, `tree`, `less`,
  `tmux`.
- Usuário não-root `agent`, com UID/GID espelhados do host via build args.

## O que é montado

- `${WORKSPACE_PATH}` (host) -> `/workspace` (contêiner): seu projeto.
- `${AGENT_HOME_PATH}` (host) -> `/home/agent` (contêiner): estado do Claude.

Os dois caminhos devem ficar fora do checkout do `sannux`. Os bind mounts do
Compose usam `create_host_path: false`, então diretórios ausentes falham cedo em
vez de serem criados no lugar errado.

## Limites de recursos

`MEM_LIMIT`, `CPU_LIMIT` e `pids_limit` são limites de recurso, não segurança.
Ajuste para sua VPS ou alocação do Docker Desktop.

## Personalizar

Edite `Dockerfile` e `compose.yml` diretamente. Adicione as ferramentas que
você usa, ative flags de segurança mais restritas (`read_only: true`,
`cap_drop: [ALL]`, `seccomp` customizado) ou troque a imagem base. Depois de
mudar o `Dockerfile`, rode `just rebuild claude-code` a partir da raiz do
repositório, ou `docker compose build --no-cache` a partir desta pasta de
template.
