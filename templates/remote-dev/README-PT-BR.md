# remote-dev

Servidor SSH remoto único para apps locais como Claude Desktop/Claude Code,
Codex App, Antigravity, VS Code Remote SSH, IDEs parecidas com Cursor e outras
ferramentas que conseguem se conectar a uma máquina Linux via SSH.

O app continua no seu computador. O servidor remoto dele, os comandos de shell,
as extensões, os caches e o acesso ao projeto rodam dentro deste contêiner.

Use este template quando você quer comodidade e isolamento para apps de
terceiros que não seguem um fluxo simples de CLI. Ele não é o melhor encaixe
para vários agentes efêmeros em paralelo. Dá para criar vários ambientes
`remote-dev`, mas cada um precisa de portas, homes, workspaces e chaves
separadas; isso consome mais recursos e aumenta a gestão. Para agentes efêmeros
de CLI, use os templates de CLI com:

```bash
docker compose run --rm agent
```

```txt
local app -> SSH -> sannux remote-dev contêiner
                    /workspace
                    /home/agent
```

## Example Vídeo (PT-BR 🇧🇷)

Example using `codex-ollama` (in Brazilian Portuguese).

[![Agentes de IA Seguros no Docker](https://i3.ytimg.com/vi/wqe0VU5L5aU/maxresdefault.jpg)](https://youtu.be/wqe0VU5L5aU)

- [youtu.be/wqe0VU5L5aU](https://youtu.be/wqe0VU5L5aU)

## O que este template entrega

- `Dockerfile`: servidor OpenSSH, Codex CLI, Node.js, Python, ferramentas de
  build e utilitários comuns de CLI.
- `compose.yml`: serviço `ssh` de longa duração no Compose profile `daemon`,
  mais um shell auxiliar não-root no serviço `agent`.
- `setup-host.sh`: cria pastas seguras no host, escreve `.env`, gera uma chave
  SSH dedicada, atualiza o bloco gerenciado de config SSH, monta a imagem,
  inicia o SSH e testa a conexão.
- `sshd_config` e `sshd-entrypoint.sh`: login SSH só por chave para o usuário
  não-root configurado.

## Setup

Do diretório raiz do repositório:

```bash
just setup remote-dev
```

O comando de setup:

- cria `templates/remote-dev/.env` quando ele não existir;
- preenche caminhos locais seguros fora deste repositório quando
  `WORKSPACE_PATH` e `AGENT_HOME_PATH` estiverem vazios;
- usa `agent` como usuário SSH e grava isso na configuração SSH gerada;
- configura o Codex para usar o contêiner como sua fronteira de sandbox;
- prepara o diretório de runtime do app-server do Codex para o tmpfs dentro do
  contêiner;
- cria uma chave SSH dedicada em `~/.ssh/sannux/`;
- instala a chave pública em `${AGENT_HOME_PATH}/.ssh/authorized_keys`;
- adiciona uma entrada gerenciada `sannux-remote-dev` em `~/.ssh/config`;
- remove entradas antigas deste template em `~/.ssh/sannux/known_hosts`;
- faz build e inicia o contêiner SSH.

Depois, conecte seu app em:

```txt
sannux-remote-dev
```

Abra esta pasta no app:

```txt
/workspace
```

## Cenários

### 1. Template

O template é um alvo genérico de Remote SSH; não é um harness para uma CLI de
agente específica. Apps locais como Codex App, Antigravity, Claude Desktop,
Claude Code, VS Code Remote SSH e ferramentas parecidas conectam via SSH e
instalam ou rodam o próprio servidor remoto dentro do contêiner.

Essa é a principal exceção ao formato dos templates de CLI: `remote-dev` foi
feito em torno de um único endpoint SSH persistente, com portas estáveis e
estado persistente.

### 2. Config inicial persistente

`.env` mais `setup-host.sh` cria o primeiro ambiente remoto funcionando.

O script de setup preenche `WORKSPACE_PATH` e `AGENT_HOME_PATH` quando eles
estão vazios, mas só com pastas dentro de `~/sannux-data`, fora deste
repositório. Esses caminhos são montados como `/workspace` e `/home/agent`
dentro do contêiner.

A home persistente guarda chaves autorizadas de SSH, autenticação/config dos
apps, extensões, caches e qualquer estado de servidor remoto escrito pelos apps
conectados.

### 3. Execução TUI persistente

Este template não fornece uma execução persistente de agente TUI. A superfície
interativa persistente é SSH:

```bash
ssh sannux-remote-dev
```

Em uma IDE ou app local, conecte no mesmo host SSH e abra `/workspace`.

### 4. Execução daemon persistente

Este é o modo principal:

```bash
docker compose --profile daemon up -d ssh
```

Da raiz do repositório:

```bash
just up remote-dev ssh
```

O serviço `ssh` mantém o mesmo workspace, home, host keys de SSH, cache de apps
e portas de preview entre reinícios.

### 5. Execução one-shot com home persistente

Para diagnóstico ou um shell comum usando o mesmo workspace e a mesma home
montados:

```bash
docker compose run --rm agent
```

Da raiz do repositório:

```bash
just run remote-dev
```

Isso é só um shell auxiliar não-root. Não é um harness one-shot dedicado para
Codex, Claude, Gemini, Pi ou opencode, e não publica as portas de preview
estáveis do serviço daemon `ssh`.

### 6. Execução one-shot com home efêmera

`remote-dev` não fornece um fluxo de agente com home efêmera. Se você precisa de
muitos agentes descartáveis e não-interativos, use um template de CLI como
`codex`, `codex-ollama`, `claude-code`, `claude-ollama`, `gemini`, `opencode` ou
`pi`.

## Uso manual

Crie os dois diretórios antes de rodar o Compose. `WORKSPACE_PATH` e
`AGENT_HOME_PATH` precisam ser caminhos absolutos no host, fora desta pasta do
template e fora do checkout deste repositório.

```bash
install -m 0600 .env.example .env
# edit WORKSPACE_PATH and AGENT_HOME_PATH
# also create both folders, plus .codex/app-server-control under AGENT_HOME_PATH
docker compose build
docker compose --profile daemon up -d ssh
```

Depois de configurar as chaves SSH, conecte com:

```bash
ssh sannux-remote-dev
```

Para um shell não-root sem SSH, útil para diagnóstico ou sessão avulsa:

```bash
docker compose run --rm agent
```

Esse serviço `agent` avulso não publica portas de preview. O serviço `ssh`, de
longa duração, publica o SSH e as portas de preview configuradas no `.env`
porque apps de Remote SSH precisam de um endpoint estável. Se você precisar de
uma porta só para um shell temporário com `agent`, publique no próprio comando:

```bash
docker compose run --rm -p 127.0.0.1:3001:3000 agent
```

## Notas de segurança

- O SSH fica preso em `127.0.0.1` por padrão.
- Login por senha está desativado.
- Login de root está desativado.
- O usuário de login SSH é `agent` por padrão.
- Usuários avançados podem alterar `REMOTE_USER` antes do setup; o script de
  setup grava o mesmo usuário em `~/.ssh/config` para que apps de Remote SSH não
  precisem adivinhar.
- Agent forwarding está desativado.
- TCP forwarding está ativado porque apps de Remote SSH costumam precisar dele.
- `~/.codex/app-server-control` é montado como tmpfs dentro do contêiner. O
  Codex App usa um socket Unix ali para sessões remotas via SSH; manter esse
  socket fora de bind mounts do host evita edge cases de permissão no filesystem
  do macOS.
- O Codex é configurado com `sandbox_mode = "danger-full-access"` dentro do
  contêiner. Isso evita um sandbox Linux aninhado frágil. O mount do contêiner é
  a fronteira, então mantenha `WORKSPACE_PATH` estreito.
- Não monte sua home real. Monte apenas a pasta do projeto que você quer que o
  app veja.

Em um VPS, prefira manter a porta SSH do contêiner privada e acessá-la por meio
do serviço SSH do host, de um túnel ou de uma regra de firewall que você
entenda.

## O que não montar

Não monte sua home real, chaves SSH, credenciais de cloud, tokens de
gerenciadores de pacotes, configuração global do Git ou GitHub, nem o socket do
Docker. Monte apenas a pasta de projeto que o app remoto deve ver, e mantenha a
`AGENT_HOME_PATH` persistente dedicada a este alvo SSH.

## O que vem dentro

- Base Debian trixie-slim fixada por digest.
- Servidor OpenSSH.
- Codex CLI.
- `bubblewrap`, exigido pelas checagens de inicialização do Codex no Linux.
- Node.js 22 LTS.
- Python 3 + pip + venv.
- `build-essential` para dependências nativas.
- Ferramentas de CLI: `git`, `rg`, `fd`, `jq`, `fzf`, `bat`, `tree`, `less`.
- Utilitários comuns de arquivo compactado usados por agentes de código e apps
  remotos.
