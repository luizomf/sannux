# opencode

[OpenCode](https://opencode.ai/docs/) rodando em um contêiner Docker
`debian-slim`.

Este template é intencionalmente simples: configure um workspace persistente e
uma agent home persistente, autentique o OpenCode uma vez e depois escolha se
cada run será interativo, one-shot persistente ou one-shot efêmero.

Runs reais autenticados com OpenCode ainda não foram testados; PRs com notas
verificadas por provider são bem-vindos.

## O que este template entrega

- `Dockerfile`: OpenCode CLI mais ferramentas comuns de desenvolvimento Linux.
- `compose.yml`: serviço do Docker Compose que monta seu projeto em
  `/workspace` e a agent home em `/home/agent`.
- `setup-host.sh`: cria as pastas no host, escreve defaults seguros no `.env` e
  prepara os diretórios de config/dados do OpenCode.

O OpenCode em si é instalado pelo pacote npm `opencode-ai`.

## Setup

Copie o arquivo de ambiente:

```bash
install -m 0600 .env.example .env
```

Idealmente, edite estes valores para deixar o workspace e a agent home
explícitos:

```env
WORKSPACE_PATH=/path/to/workspaces/my-project
AGENT_HOME_PATH=/path/to/agent-homes/opencode
```

Se `WORKSPACE_PATH` e `AGENT_HOME_PATH` ficarem vazios, o `setup-host.sh` usa
este fallback:

```txt
~/sannux-data/workspaces/opencode
~/sannux-data/agent-homes/opencode
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
just setup opencode
just run opencode
```

## Cenários

### 1. Template

O template é o ambiente específico do harness: `opencode` significa OpenCode CLI
rodando com seu próprio workspace e sua agent home isolada.

Outros templates seguem a mesma ideia para outros harnesses, como Codex, Claude,
Gemini, Hermes ou Pi.

### 2. Config inicial persistente

`.env` mais `setup-host.sh` cria a primeira agent home funcional.

Autentique o OpenCode com uma destas opções:

- defina chaves de provider como `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`,
  `GEMINI_API_KEY`, `GROQ_API_KEY` ou `OPENROUTER_API_KEY` no `.env`;
- rode `docker compose run --rm agent auth login` e escolha um provider;
- rode a TUI do OpenCode e use `/connect`.

A documentação do OpenCode diz que `opencode auth login` grava credenciais em
`~/.local/share/opencode/auth.json`. Neste template, isso fica em:

```txt
${AGENT_HOME_PATH}/.local/share/opencode/auth.json
```

A config global do OpenCode fica em `~/.config/opencode/opencode.json`, com
config da TUI em `~/.config/opencode/tui.json`. A config do projeto também pode
ficar em `opencode.json` ou `.opencode/` dentro de `/workspace`.

Trate a agent home inteira como privada. Ela pode conter credenciais de
provider, config global, cópias de config do projeto, sessões, snapshots,
histórico, cache, tokens OAuth de MCP, plugins, skills, logs e outros estados
de runtime.

### 3. Execução TUI persistente

Use isto para trabalho interativo normal:

```bash
docker compose run --rm agent
```

A partir da raiz do repositório:

```bash
just run opencode
```

Esse run fica ativo até você sair da TUI. Ele usa o workspace persistente e a
agent home persistente do `.env`.

### 4. Execução daemon persistente

Este template ainda não fornece um serviço daemon do OpenCode.

A documentação da OpenCode CLI inclui `opencode serve`, `opencode web` e
`opencode attach`, mas este template não foi validado com credenciais reais como
um perfil de servidor de longa duração. Até isso ser testado, prefira a TUI
interativa ou os runs one-shot abaixo. Se um perfil daemon for adicionado no
futuro, documente aqui suas portas, autenticação, logs e fluxo de parada.

### 5. Run one-shot com home persistente

Use isto quando compartilhar a mesma agent home for aceitável:

```bash
docker compose run --rm -T agent run "Summarize the mounted project."
```

A partir da raiz do repositório:

```bash
just run opencode run "Summarize the mounted project."
```

A documentação do OpenCode descreve `opencode run [message..]` como modo
não-interativo para scripts e automações.

Por padrão, as permissões do OpenCode são permissivas: a maioria das operações é
permitida, enquanto `doom_loop` e `external_directory` pedem aprovação.
Configure `permission` em `opencode.json` quando quiser que leituras, edições,
comandos shell ou diretórios externos peçam aprovação ou sejam negados. Um
one-shot read-only pode usar uma config de projeto assim:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "*": "ask",
    "edit": "deny",
    "bash": "ask"
  }
}
```

Para tarefas de escrita sem operador, deixe o tradeoff de permissão explícito:

```bash
docker compose run --rm -T agent run \
  --dangerously-skip-permissions \
  "Create /workspace/test.txt with the current date in ISO 8601 format."
```

O `opencode run --help` local descreve `--dangerously-skip-permissions` como:
autoaprovar permissões que não foram explicitamente negadas. Mantenha regras
`deny` explícitas na config para qualquer coisa que o run nunca deve fazer.

Isso é simples, mas o run pode ler e escrever a `AGENT_HOME_PATH` persistente
inteira: auth, settings, sessões, snapshots, cache, logs, histórico, config de
MCP, plugins, skills e estado de runtime.

### 6. Run one-shot com home efêmera

Use isto quando quiser uma `/home/agent` nova para um único comando.

Com API keys de provider no `.env`, uma home temporária vazia deve bastar:

```bash
template_dir=/path/to/sannux/templates/opencode
tmp_workspace=/path/to/tmp/workspace-1
tmp_home="$(mktemp -d)"
trap 'rm -rf "$tmp_home"' EXIT

mkdir -p "$tmp_workspace"
mkdir -p "$tmp_home/.config/opencode" "$tmp_home/.local/share/opencode"

docker compose --project-directory "$template_dir" run \
  -v "$tmp_workspace:/workspace" \
  -v "$tmp_home:/home/agent" \
  --rm -T agent \
  run --dangerously-skip-permissions \
  "Create /workspace/test.txt with the current date in ISO 8601 format."
```

Para prompts read-only, deixe `--dangerously-skip-permissions` de fora e use uma
config `permission` do OpenCode que peça aprovação ou negue escritas e comandos
shell:

```bash
docker compose --project-directory "$template_dir" run \
  -v "$tmp_workspace:/workspace" \
  -v "$tmp_home:/home/agent" \
  --rm -T agent \
  run "Summarize the mounted project."
```

Se você depende de `opencode auth login`, `/connect`, OAuth de MCP, plugins,
skills ou config global do OpenCode da home persistente, copie apenas o estado
que aceita expor ao run:

```bash
persistent_home=/path/to/agent-homes/opencode
test -d "$persistent_home/.config/opencode"
test -d "$persistent_home/.local/share/opencode"
rm -rf "$tmp_home/.config/opencode" "$tmp_home/.local/share/opencode"
mkdir -p "$tmp_home/.config" "$tmp_home/.local/share"
cp -R "$persistent_home/.config/opencode" "$tmp_home/.config/opencode"
cp -R "$persistent_home/.local/share/opencode" "$tmp_home/.local/share/opencode"
```

Aviso curto: Docker `-v` pode criar pastas ausentes no host. Crie e confira as
pastas você mesmo quando o caminho importar.

Outro aviso: `.config/opencode` e `.local/share/opencode` podem conter
credenciais reais de provider, tokens OAuth de MCP, config global, plugins,
skills, sessões, snapshots, histórico, cache, logs ou outro estado privado.
Copie esses caminhos apenas para runs onde você aceita expor esse estado.

## Portas de preview

O serviço regular `agent` não publica portas fixas no host por padrão. Se o
OpenCode subir um app dentro de um run, publique só a porta necessária naquele
comando:

```bash
docker compose run --rm -p 127.0.0.1:3001:3000 agent
```

Isso mapeia a porta `3001` do host para a porta `3000` do contêiner naquela
sessão. Faça o app dentro do contêiner escutar em `0.0.0.0`. Em uma VPS, exponha
`0.0.0.0:PORTA_HOST:PORTA_CONTAINER` apenas quando realmente quiser acesso
público.

## O que vem dentro

- Base `debian trixie-slim` fixada por digest.
- Node.js 22 LTS + OpenCode CLI (`opencode-ai`).
- Python 3 + pip + venv, para o agente conseguir abrir tarefas em Python.
- `build-essential` para projetos com dependências nativas.
- Utilitários de CLI: `git`, `rg`, `fd`, `jq`, `fzf`, `bat`, `tree`, `less`.
- Usuário não-root `agent`, com UID/GID alinhados ao host via build args.

## O que não montar

Não monte casualmente:

- sua home real;
- chaves SSH;
- credenciais de cloud;
- tokens de package managers;
- config global de Git ou GitHub;
- o socket do Docker.

Monte a pasta do projeto que o OpenCode deve editar e monte apenas os dados do
OpenCode que você aceita expor para aquele run.

## Personalização

Edite `Dockerfile` e `compose.yml` diretamente. Adicione ferramentas que você
usa, ative flags de segurança mais rígidas (`read_only: true`, `cap_drop:
[ALL]`, `seccomp` customizado) ou troque a imagem base. Depois de mudar a
imagem:

```bash
docker compose build --no-cache
```
