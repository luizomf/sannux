# hermes

[Hermes Agent](https://github.com/NousResearch/hermes-agent) rodando em Docker.
O Hermes não é só um agente de terminal: ele também pode rodar um gateway 24/7
para mensagens, webhooks, tarefas agendadas e um dashboard web local.

Este template mantém o Hermes dentro de um contêiner Debian-slim com usuário
não-root, seu código montado em `/workspace`, e auth/config/estado do Hermes
persistidos em uma agent home explícita no host.

## Example Vídeo (PT-BR 🇧🇷)

Example using `codex-ollama` (in Brazilian Portuguese).

[![Agentes de IA Seguros no Docker](https://i3.ytimg.com/vi/wqe0VU5L5aU/maxresdefault.jpg)](https://youtu.be/wqe0VU5L5aU)

- [youtu.be/wqe0VU5L5aU](https://youtu.be/wqe0VU5L5aU)

## O que este template entrega

- `Dockerfile`: Hermes Agent mais ferramentas comuns de desenvolvimento Linux.
- `compose.yml`: um serviço interativo `agent` mais serviços `gateway` e
  `dashboard` no perfil daemon.
- `setup-host.sh`: cria as pastas no host, escreve defaults seguros no `.env` e
  prepara `${AGENT_HOME_PATH}/.hermes`.
- `HERMES_HOME=/home/agent/.hermes`: o estado do Hermes cai dentro da agent home
  montada, não na camada da imagem.
- O venv Python gerenciado pelo Hermes fica no `PATH`, então `python` existe
  dentro do contêiner enquanto as dependências seguem gerenciadas pela imagem.
- CLIs opcionais de delegação, como Codex, Claude Code, Gemini, Pi ou opencode,
  não vêm embutidas. Adicione só as ferramentas que você realmente quer que o
  Hermes chame.

## Setup

Copie o arquivo de ambiente:

```bash
install -m 0600 .env.example .env
```

Idealmente, edite estes valores para deixar workspace e agent home explícitos:

```env
WORKSPACE_PATH=/srv/example-data/workspaces/my-project
AGENT_HOME_PATH=/srv/example-data/agent-homes/hermes
```

Se `WORKSPACE_PATH` e `AGENT_HOME_PATH` ficarem vazios, o `setup-host.sh` usa
este fallback:

```txt
~/sannux-data/workspaces/hermes
~/sannux-data/agent-homes/hermes
```

Crie as pastas no host e preencha valores ausentes no `.env`:

```bash
./setup-host.sh
```

Rode o wizard de setup do Hermes e teste a TUI uma vez:

```bash
docker compose run --rm agent setup
docker compose run --rm agent
```

A partir da raiz do repositório, o mesmo fluxo é:

```bash
just setup hermes
just run hermes setup
just run hermes
```

Use `hermes setup` para o wizard completo, `hermes model` quando você só
precisar configurar provider/model/auth, e `hermes gateway setup` apenas depois
que uma conversa normal no CLI funcionar.

Se você usar um endpoint OpenAI-compatível customizado, mantenha essa chave de
provider no `.env` deste template ou cole-a pelo wizard de setup/model do
Hermes. Não coloque credenciais compartilhadas de cloud, GitHub, npm ou SSH no
workspace montado.

## Cenários

### 1. Template

O template é o ambiente específico do harness: `hermes` significa Hermes Agent
configurado para uso via CLI e para o gateway opcional sempre ligado.

Outros templates seguem a mesma ideia para outros harnesses, como Codex, Claude
Code, Gemini, Pi ou opencode.

### 2. Config inicial persistente

`.env` mais `setup-host.sh` cria a primeira agent home. Ele não roda o wizard
interativo do Hermes por você.

O Hermes guarda estado importante de usuário em `/home/agent/.hermes/`: auth de
provider, config, sessões, logs, memória, configurações de tools, hooks, skills,
config de plataformas do gateway, allowlists, estado de cron/webhook, cache e
outros estados de runtime. Trate esse diretório como privado.

Essa persistência é o ponto forte do Hermes, não só um detalhe de implementação.
O Hermes foi desenhado para melhorar com memória, recall de sessões e skills
reutilizáveis salvas a partir da experiência. Para uso normal do Hermes,
mantenha uma home persistente intencional e deixe ela acumular contexto útil.

A TUI e o daemon `gateway` usam intencionalmente o mesmo `WORKSPACE_PATH` e
`AGENT_HOME_PATH` persistentes. Isso dá ao gateway a mesma identidade Hermes e o
mesmo workspace configurado que você testou interativamente.

### 3. Execução TUI persistente

Use isto para trabalho interativo normal:

```bash
docker compose run --rm agent
```

A partir da raiz do repositório:

```bash
just run hermes
```

Esta run fica ativa até você sair da TUI. Ela usa o workspace persistente e a
agent home persistente do `.env`.

Para abrir um shell interativo em vez do Hermes:

```bash
docker compose run --rm --entrypoint bash agent
```

### 4. Execuções daemon persistentes

Use isto quando quiser deixar o gateway do Hermes rodando em segundo plano para
mensagens, webhooks e jobs estilo cron:

```bash
docker compose --profile daemon up -d gateway
docker compose logs -f gateway
docker compose stop gateway
```

A partir da raiz do repositório:

```bash
just up hermes gateway
just logs hermes gateway
just ps hermes
just down hermes
```

O daemon executa:

```bash
hermes gateway run --replace --accept-hooks
```

No Docker, use `gateway run`, não `gateway start` nem `gateway install`, porque
`start/install` miram systemd ou launchd no host. Os cron jobs do Hermes são
criados com `hermes cron ...`, mas disparam a partir do scheduler em segundo
plano do gateway em execução.

Rode a configuração do gateway apenas depois que o CLI funcionar:

```bash
docker compose run --rm agent gateway setup
```

O gateway publica as portas de preview configuradas em `HOST_PORT_*` porque é um
endpoint remoto persistente. Em uma VPS, configure `PORT_BIND_ADDRESS=0.0.0.0`
apenas quando você realmente quiser expor essas portas.

Use isto quando quiser o dashboard do Hermes no navegador para config, API keys,
sessões e status:

```bash
docker compose --profile daemon up -d dashboard
docker compose logs -f dashboard
docker compose stop dashboard
```

A partir da raiz do repositório:

```bash
just up hermes dashboard
just logs hermes dashboard
just ps hermes
just down hermes
```

O dashboard executa:

```bash
hermes dashboard --host 0.0.0.0 --port 9119 --no-open --insecure --skip-build
```

Dentro do contêiner ele precisa escutar em `0.0.0.0` para o Docker publicar a
porta. O lado do host ainda usa `${PORT_BIND_ADDRESS}` e o default é
`127.0.0.1`. Mantenha assim, a menos que você coloque o dashboard atrás de um
firewall ou reverse proxy real. O dashboard pode gerenciar config e API keys do
Hermes, então trate-o como sensível.

### 5. Execução one-shot com home persistente

Use isto quando compartilhar a mesma agent home for aceitável. No Hermes, este é
o modo one-shot normal porque preserva a mesma memória, skills, auth e config de
tools usadas pela TUI e pelo gateway:

```bash
docker compose run --rm -T agent -z \
  "Resuma este projeto."
```

`hermes -z` é a entrada one-shot programática: passe o prompt como argumento do
`-z`, não via stdin. O Hermes carrega tools, memória, rules e `AGENTS.md`
normalmente, mas bypassa approvals automaticamente porque esse modo é pensado
para scripts. Isso é simples, mas a run pode ler e escrever no `AGENT_HOME_PATH`
persistente inteiro: auth, config, sessões, logs, memória, skills, hooks, estado
do gateway, estado de cron/webhook, cache e outros estados de runtime.

Use isto apenas quando o Docker for a fronteira de sandbox que você quer para o
comando:

```bash
docker compose run --rm -T agent -z \
  "Revise este repo e sugira correções."
```

Você também pode sobrescrever o workspace para um comando:

```bash
tmp_workspace=/srv/example-data/tmp/workspace-1
mkdir -p "$tmp_workspace"

docker compose run \
  -v "$tmp_workspace:/workspace" \
  --rm -T agent \
  -z \
  "Resuma este workspace temporário."
```

Isso ainda usa a agent home persistente do `.env`; só `/workspace` é sobrescrito
para aquele comando.

### 6. Execução one-shot com home efêmera

Este não é o fluxo principal do Hermes. O Hermes fica mais forte quando a mesma
home `.hermes` persiste entre sessões, para que memória, skills, sessões e
estado do gateway acumulem com o tempo.

Use uma home efêmera apenas para testes descartáveis de Docker/sandbox quando
você intencionalmente não quer que a run ensine ou altere sua identidade Hermes
de longa duração. Uma home temporária útil geralmente ainda precisa do diretório
`.hermes` já testado para auth e config. O conjunto mínimo estável de arquivos
não está documentado de forma estreita o suficiente para este template, então
copie o diretório inteiro só para runs em que você aceita expor esse estado.

```bash
template_dir=/srv/sannux/templates/hermes
tmp_workspace=/srv/example-data/tmp/workspace-1
persistent_home=/srv/example-data/agent-homes/hermes
tmp_home="$(mktemp -d)"
trap 'rm -rf "$tmp_home"' EXIT

mkdir -p "$tmp_workspace"
test -d "$persistent_home/.hermes"
cp -R "$persistent_home/.hermes" "$tmp_home/.hermes"
chmod -R go-rwx "$tmp_home"

docker compose --project-directory "$template_dir" run \
  -v "$tmp_workspace:/workspace" \
  -v "$tmp_home:/home/agent" \
  --rm -T agent \
  -z \
  "Resuma este workspace temporário."
```

Aviso curto: Docker `-v` pode criar pastas ausentes no host. Crie e confira as
pastas você mesmo quando o caminho importar.

Não use uma home efêmera copiada para o uso normal do Hermes nem para o gateway
24/7. Qualquer nova memória, sessão, skill, estado do gateway, auth de
mensageria, allowlist, cron job ou config de webhook escrita durante essa run
some junto com `tmp_home`.

## Portas de preview

O serviço `agent` comum não publica portas fixas no host por padrão. Se o Hermes
subir um app dentro de uma run, publique só a porta necessária naquele comando:

```bash
docker compose run --rm -p 127.0.0.1:3001:3000 agent
```

Isso mapeia a porta `3001` do host para a porta `3000` do contêiner naquela
sessão. Faça o app dentro do contêiner escutar em `0.0.0.0`.

O gateway sempre ligado publica os valores configurados em `HOST_PORT_*` porque
ele é um endpoint remoto persistente.

## Roteamento de modelo com endpoints customizados

O Hermes pode usar um único endpoint compatível com OpenAI para o modelo
principal e ainda sobrescrever tarefas auxiliares mais baratas. Exemplo:

```bash
docker compose run --rm agent model
```

Escolha o provider de endpoint customizado e depois use:

```txt
URL base da API: https://models.example.com/v1
Nome do modelo: router:example-model-router
```

Ou use um slug de modelo específico em vez de `router:...`. Se você mantiver a
chave em `.env`, nomeie-a como `MODEL_ACCESS_KEY` e referencie-a de
`~/.hermes/config.yaml` para tarefas auxiliares.

A ideia importante não é um fornecedor específico. É que o modelo principal
caro, o modelo barato de compression/session-search, o modelo MCP e o fallback
podem ser escolhidos separadamente enquanto as credenciais ficam dentro desta
home do Hermes.

O Hermes ainda não expõe headers de request customizados, como
`X-Model-Affinity`, pela CLI. Não adicione um proxy aqui a menos que você tenha
um problema real de cache locality ou custo para resolver.

## Checklist de segurança do gateway

Antes de deixar o gateway rodando numa VPS:

- Configure usuários permitidos para cada plataforma de mensageria no arquivo de
  env do Hermes, em `${AGENT_HOME_PATH}/.hermes/.env`, por exemplo
  `TELEGRAM_ALLOWED_USERS=123456789` ou `GATEWAY_ALLOWED_USERS=123456789`.
- Mantenha as approvals do Hermes ativas. Use `approvals.mode: manual` ou
  `smart`; não desligue isso para um agente sempre ativo, a menos que seja um
  laboratório descartável.
- Comece pelo CLI, depois adicione gateways, cron jobs, servidores MCP e
  ferramentas de browser/voz uma de cada vez.
- Mantenha o dashboard preso ao localhost por padrão. Se você expuser isso em
  uma VPS, coloque firewall ou reverse proxy real na frente antes de trocar
  `PORT_BIND_ADDRESS` para `0.0.0.0`.
- Deixe os comandos de terminal do Hermes no backend local do contêiner. Não
  monte o Docker socket do host só para fazer Docker aninhado funcionar; isso
  furaria a fronteira principal do sandbox.

## Receitas

A partir da raiz do repositório, com `just`:

```bash
just setup hermes
just config hermes
just build hermes
just rebuild hermes
just run hermes setup
just run hermes model
just run hermes
just up hermes gateway
just up hermes dashboard
just logs hermes gateway
just logs hermes dashboard
just down hermes
just shell hermes
```

A partir desta pasta de template, sem `just`:

```bash
./setup-host.sh
docker compose config --no-env-resolution
docker compose build
docker compose build --no-cache
docker compose run --rm agent setup
docker compose run --rm agent model
docker compose run --rm agent
docker compose --profile daemon up -d gateway
docker compose --profile daemon up -d dashboard
docker compose logs -f gateway
docker compose logs -f dashboard
docker compose stop gateway
docker compose stop dashboard
docker compose run --rm --entrypoint bash agent
docker compose down -v
```

## O que tem dentro

Aviso: esta imagem é significativamente maior que as outras templates porque o
Hermes é uma codebase Python com superfície ampla, não um simples CLI em npm.

- Base Debian trixie-slim fixada por digest.
- Hermes Agent instalado pelo `install.sh` oficial com código em
  `/usr/local/lib/hermes-agent` e comando em `/usr/local/bin/hermes`.
- `uv` mais Python 3.11, gerenciados pelo instalador do Hermes.
- Extra `[all]` curado do Hermes mais `[messaging]`, então o gateway tem
  dependências de adapters Telegram, Discord e Slack disponíveis em runtime.
- Frontend do dashboard compilado em
  `/usr/local/lib/hermes-agent/hermes_cli/web_dist/`, então
  `hermes dashboard --skip-build` funciona no Docker.
- `ffmpeg`, `build-essential`, `python3-dev`, `libffi-dev` para voz, transcrição
  e wheels Python nativas.
- Utilitários de CLI: `git`, `rg`, `fd`, `jq`, `fzf`, `bat`, `tree`, `less`.
- Usuário não-root `agent`, com UID/GID espelhados do host via build args.

Se você não precisar da stack de voz/transcrição, pode editar o Dockerfile para
remover `ffmpeg` e extras que não vai usar. Veja os
[flags do instalador do Hermes](https://github.com/NousResearch/hermes-agent/blob/main/scripts/install.sh)
para os controles disponíveis.

## O que é montado

- `${WORKSPACE_PATH}` (host) -> `/workspace` (contêiner): seu projeto.
- `${AGENT_HOME_PATH}` (host) -> `/home/agent/` (contêiner): `HERMES_HOME` vive
  aqui como `~/.hermes/`.

O código do Hermes fica em `/usr/local/lib/hermes-agent` dentro da imagem, não
no bind mount, então o mount não cobre a instalação. O contêiner é efêmero
(`--rm`); destrua e recrie sem perder estado.

Os dois caminhos do host são obrigatórios e devem ficar fora do checkout
`sannux`. O Compose usa `create_host_path: false`, então diretórios ausentes
falham cedo em vez de serem criados silenciosamente no lugar errado.

## O que não montar

Não monte casualmente:

- sua home real;
- chaves SSH;
- credenciais de cloud;
- tokens de gerenciadores de pacote;
- config global de Git ou GitHub;
- o Docker socket.

Chaves de provider pertencem ao `.env` deste template ou ao estado de
config/auth do Hermes em `${AGENT_HOME_PATH}/.hermes`, sempre escopadas para
este agente.

## O que não está incluído

Por design, este template é a base sleep-tight, não o máximo paranoico. De
saída:

- O tráfego de rede de saída está aberto.
- O agente recebe as capacidades Linux padrão.
- O root filesystem não é somente leitura.
- Não há passthrough de GPU.

O que você ganha: o agente não acessa `~/.ssh/`, `~/.aws/`, `~/.config/gh/`,
`~/.npmrc` nem qualquer outra coisa fora do workspace montado e da agent home, a
menos que você monte isso.

## Personalizar

Edite `Dockerfile` e `compose.yml` diretamente. Adicione as ferramentas que você
usa, ative flags de segurança mais restritas, passe `--gpus` para servir modelos
localmente ou troque a imagem base. Depois de mudar o `Dockerfile`, rode
`just rebuild hermes` a partir da raiz do repositório ou
`docker compose build --no-cache` a partir desta pasta de template.

### Instalando ferramentas extras

Contêineres são descartáveis. Se você instalar um pacote em um shell interativo,
essa mudança some quando o contêiner é removido. Para mudanças repetíveis, edite
o `Dockerfile` e reconstrua a imagem.

O Hermes consegue delegar trabalho para muitas ferramentas externas quando elas
existem no contêiner, mas este template intencionalmente não pré-instala toda
CLI de agente possível. Codex, Claude Code, Gemini, Pi, opencode e harnesses
parecidos têm seus próprios modelos de instalação, auth, atualização e
segurança. Adicione no `Dockerfile` só o que você precisa, fixe versões quando o
instalador permitir e valide cada CLI com `--version` ou um smoke test durante o
build.

Por exemplo, mantenha ferramentas opcionais de delegação em um bloco local
óbvio:

```dockerfile
# Ponto local opcional para ferramentas que o Hermes pode chamar.
# Troque os placeholders pelos comandos oficiais de instalação em que confia.
RUN set -eux; \
    install-your-agent-cli-here; \
    your-agent-cli --version
```

Se uma CLI de agente for baseada em Node, instale Node em um local normal de
runtime antes de instalar essa CLI. Não dependa da cópia privada em
`/root/.hermes/node` usada para compilar o frontend do dashboard do Hermes; ela
não faz parte do contrato de runtime do usuário não-root `agent`.

Para pacotes Debian, adicione-os na lista do `apt-get install`:

```dockerfile
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        seu-pacote-aqui \
    && rm -rf /var/lib/apt/lists/*
```

Para dependências Python do Hermes, instale no venv gerenciado pelo Hermes
durante o build da imagem, não como usuário `agent` em runtime:

```dockerfile
RUN cd /usr/local/lib/hermes-agent \
    && UV_PROJECT_ENVIRONMENT=/usr/local/lib/hermes-agent/venv \
        /root/.local/bin/uv sync --extra all --extra messaging --locked
```

Se você precisar de outro extra upstream do Hermes, adicione outro
`--extra nome` ali e valide com um import ou comando no mesmo bloco `RUN`. Se
precisar de um pacote Python arbitrário que não está no lockfile do Hermes, fixe
a versão deliberadamente e entenda que ele fica fora do conjunto de dependências
hash-locked do Hermes.

Não dependa de `pip install` dentro de
`docker compose run --rm --entrypoint bash agent`: o venv do Hermes é gerenciado
pela imagem e root-owned de propósito.
