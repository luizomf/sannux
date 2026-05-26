# claude-ollama

Claude Code rodando em Docker, apontado para um servidor Ollama através de um
endpoint compatível com Anthropic.

Este template é propositalmente pequeno: configure uma agent home persistente,
teste uma vez na TUI e depois mude só os argumentos do Claude em cada execução.

## Example Vídeo (PT-BR 🇧🇷)

Example using `codex-ollama` (in Brazilian Portuguese).

[![Agentes de IA Seguros no Docker](https://i3.ytimg.com/vi/wqe0VU5L5aU/maxresdefault.jpg)](https://youtu.be/wqe0VU5L5aU)

- [youtu.be/wqe0VU5L5aU](https://youtu.be/wqe0VU5L5aU)

## O que este template entrega

- `Dockerfile`: Claude Code e ferramentas comuns de desenvolvimento em Linux.
- `compose.yml`: monta seu projeto em `/workspace` e a agent home em
  `/home/agent`.
- `setup-host.sh`: cria as pastas no host e escreve defaults seguros no `.env`.

O Ollama em si roda fora deste contêiner.

## Setup

Copie o arquivo de ambiente:

```bash
install -m 0600 .env.example .env
```

O ideal é editar estes valores para deixar workspace e agent home explícitos:

```env
WORKSPACE_PATH=/path/to/workspaces/my-project
AGENT_HOME_PATH=/path/to/agent-homes/claude-ollama
ANTHROPIC_BASE_URL=http://host.docker.internal:11434
ANTHROPIC_MODEL=example-ollama-model
```

Se `WORKSPACE_PATH` e `AGENT_HOME_PATH` ficarem vazios, o `setup-host.sh` usa
este fallback:

```txt
~/sannux-data/workspaces/claude-ollama
~/sannux-data/agent-homes/claude-ollama
```

Crie as pastas no host e preencha valores ausentes no `.env`:

```bash
./setup-host.sh
```

Teste a TUI uma vez:

```bash
docker compose run --rm agent
```

Da raiz do repositório, o mesmo fluxo é:

```bash
just setup claude-ollama
just run claude-ollama
```

## Cenários

### 1. Template

O template é o ambiente específico do harness: `claude-ollama` significa Claude
Code configurado para usar um endpoint Ollama.

Outros templates seguem a mesma ideia para outros harnesses, como Codex, Claude,
Gemini, Pi ou opencode.

### 2. Config inicial persistente

`.env` mais `setup-host.sh` cria a primeira agent home funcionando.

Neste harness, o roteamento para o Ollama é só variável de ambiente:
`ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_API_KEY` e
`ANTHROPIC_MODEL`.

A agent home ainda importa. O Claude Code pode guardar settings, sessões, logs,
cache, histórico de shell, plugins, config de MCP e outros estados de runtime em
`/home/agent`.

### 3. Execução TUI persistente

Use isso para o trabalho interativo normal:

```bash
docker compose run --rm agent
```

Da raiz do repositório:

```bash
just run claude-ollama
```

Isso compartilha o workspace persistente e a agent home persistente do `.env`.

### 4. Execução daemon persistente

Este template não fornece serviço daemon do Claude/Ollama.

O Claude Code roda como TUI interativa ou como comando one-shot contra o
endpoint compatível com Ollama configurado. Se um perfil daemon for adicionado
depois, documente aqui portas, autenticação, logs e fluxo de parada.

### 5. Execução one-shot com home persistente

Use quando compartilhar a mesma agent home for aceitável:

```bash
printf '%s\n' "Resuma este projeto." | \
  docker compose run --rm -T agent \
    --dangerously-skip-permissions --no-session-persistence -p -
```

É simples, mas a execução pode ler e escrever a `AGENT_HOME_PATH` inteira:
settings, sessões, cache, logs, histórico, plugins, config de MCP e estado de
runtime. `--no-session-persistence` diz ao Claude Code para não salvar aquela
conversa.

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

Use quando você quiser uma `/home/agent` nova para um comando, reaproveitando os
arquivos de estado do Claude que o `setup-host.sh` preparou na home persistente:

```bash
template_dir=/path/to/templates/claude-ollama
tmp_workspace=/path/to/workspaces/tmp/workspace-1
persistent_home=/path/to/agent-homes/claude-ollama
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

Para Ollama, o `setup-host.sh` cria um `.claude.json` mínimo com
`firstStartTime`. O Claude Code ainda espera esse formato de arquivo. O exemplo
copia o estado do Claude para a home temporária em vez de fazer bind mount de
arquivos aninhados, porque o Docker pode criar fontes de arquivo ausentes como
diretórios e mounts de arquivo dentro de `/home/agent` são frágeis. Se a sua
home persistente depois tiver auth real do Claude ou estado customizado,
inspecione `.claude` e `.claude.json` antes de copiar esses caminhos para um run
efêmero.

## Portas de preview

Se o agente subir um app dentro do contêiner, publique só a porta necessária
para aquele run:

```bash
docker compose run --rm -p 127.0.0.1:3001:3000 agent
```

Faça o app escutar em `0.0.0.0` dentro do contêiner. Em uma VPS, exponha
`0.0.0.0:PORTA_HOST:PORTA_CONTAINER` só quando você realmente quiser acesso
público.

## Raciocínio / thinking

O Claude Code expõe a flag `--effort`:

```bash
docker compose run --rm agent --effort high
```

Essa flag pertence ao harness Claude Code. Os valores válidos são `low`,
`medium`, `high`, `xhigh` e `max`. Valores como `false` são rejeitados antes da
requisição chegar no Ollama.

Com o Ollama, se o effort muda algo depende do endpoint compatível com Anthropic
e do modelo. Se o seu modelo tem controles nativos de thinking, trate isso como
detalhe do modelo/provedor do Ollama, não como algo que este template Docker
consegue garantir.

## Modelo de permissão

Este template executa o Claude Code com:

```bash
--dangerously-skip-permissions
```

Isso é intencional aqui: o Docker é a fronteira do sandbox. O agente consegue
ver o workspace montado, a agent home montada e a rede.

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

## O que tem dentro

- Base Debian trixie-slim fixada por digest.
- Node.js 22 LTS + Claude Code (`@anthropic-ai/claude-code`).
- Python 3 + pip + venv.
- `build-essential` para projetos com dependências nativas.
- Utilitários de CLI: `git`, `rg`, `fd`, `jq`, `fzf`, `bat`, `tree`, `less`.
- Usuário não-root `agent`, com UID/GID espelhados do host via build args.

## O que é montado

- `${WORKSPACE_PATH}` (host) -> `/workspace` (contêiner): seu projeto.
- `${AGENT_HOME_PATH}` (host) -> `/home/agent` (contêiner): estado do Claude.

Os dois caminhos devem ficar fora do checkout do `sannux`. Os bind mounts do
Compose usam `create_host_path: false`, então diretórios ausentes falham cedo em
vez de serem criados no lugar errado.

## Limites de recursos

`MEM_LIMIT`, `CPU_LIMIT` e `pids_limit` são limites de recurso, não segurança.
Ajuste-os para a sua VPS ou para a alocação do Docker Desktop.

## Personalizar

Edite `Dockerfile` e `compose.yml` diretamente. Adicione as ferramentas que você
usa, ajuste o roteamento do Ollama ou deixe as configurações do Compose mais
restritas para o seu deploy. Depois de alterar a imagem:

```bash
docker compose build --no-cache
```
