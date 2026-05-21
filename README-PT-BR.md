# sannux

**Sandbox Linux**: Modelos Docker para executar agentes de codificação de IA em
contêineres isolados.

O objetivo é simples: dar ao agente um diretório inicial Linux útil, ferramentas
e uma pasta de projeto, sem conceder acesso ao seu diretório inicial real do
host.

Modelos atuais:

| Modelo          | O que executa                    | Melhor para                                                     |
| --------------- | -------------------------------- | --------------------------------------------------------------- |
| `claude-code`   | Claude Code CLI                  | Fluxo de trabalho Anthropic/Claude Code                         |
| `claude-ollama` | Claude Code apontado para Ollama | Ambiente Claude Code com um modelo local/aberto                 |
| `codex`         | OpenAI Codex CLI                 | Fluxo de trabalho Codex com login/API da OpenAI                 |
| `codex-ollama`  | Codex CLI apontado para Ollama   | Ambiente Codex com um modelo local/aberto                       |
| `gemini`        | Gemini CLI                       | Fluxo de trabalho Google Gemini                                 |
| `hermes`        | Hermes Agent                     | mensagens, webhooks, automações estilo cron                     |
| `opencode`      | opencode CLI                     | Fluxo de trabalho de agente terminal independente de modelo     |
| `pi`            | Pi Coding Agent                  | Agente de codificação focado em terminal com configuração local |
| `remote-dev`    | Servidor SSH remoto único        | apps externos/IDEs com Remote SSH                               |

Cada modelo reside em `templates/<template>/` e é autossuficiente. Você pode
clonar o repositório inteiro e usar o `justfile` na raiz, ou copiar uma pasta de
modelo para um VPS e usar o Docker Compose convencional.

## Conceitos centrais

Estas palavras têm significados específicos neste repositório:

- **Template**: uma definição reutilizável de ambiente: Dockerfile, serviço do
  Compose, ferramentas, entrypoint, limites de recursos e ligação padrão.
  Exemplos: `codex`, `codex-ollama`, `claude-code` e `remote-dev`.
- **Config inicial persistente**: a primeira agent home funcionando para um
  template. Normalmente vem de `.env` mais um script de setup.
- **Run**: uma execução concreta de um template, com workspace, agent home,
  comando, logs e status de saída. Um run pode ser interativo, de execução
  única, agendado ou prolongado.
- **Agent home**: o diretório do host montado em `/home/agent` para um run. É
  onde a CLI pode gravar estado de runtime, como autenticação, configuração,
  sessões, logs, cache, memória e histórico local.
- **Agente persistente**: uma identidade de agente que reutiliza a mesma agent
  home entre runs. Isso é útil para sessões TUI, login manual e trabalhos em que
  manter estado é intencional.
- **Run efêmero**: um run com uma agent home temporária criada a partir de um
  template ou config. É útil para automações YOLO sem operador, cron jobs e runs
  sobrepostos que não devem compartilhar a home inteira da CLI.
- **Serviço daemon**: um serviço de longa duração gerenciado pelo Compose, como
  SSH do `remote-dev`, Hermes `gateway`/`dashboard` ou Claude Code
  `remote-control`. Ele tem ciclo de vida de serviço: `up`, `logs`, `stop`,
  portas estáveis e estado persistente.

Um template define como rodar. A config inicial te dá uma agent home
funcionando. Um run é uma execução. Um serviço daemon fica vivo.

O contrato completo entre templates fica em
[docs/template-contract.md](docs/template-contract.md). Rode `just check` antes
de finalizar mudanças em templates ou na documentação de contrato; ele valida
estrutura, não os seus valores locais.

Quando a distinção importar, evite usar `agente` sozinho. Prefira termos
precisos como `agente de CLI`, `sessão TUI`, `run efêmero`,
`agente persistente`, `serviço daemon` e `agent home`.

## Índice

- [1. A ideia](#1-a-ideia)
- [2. O que isso protege](#2-o-que-isso-protege)
- [3. As duas pastas que importam](#3-as-duas-pastas-que-importam)
- [4. Primeira execução com Codex](#4-primeira-execução-com-codex)
- [5. Usando just](#5-usando-just)
- [6. Usando Docker Compose convencional](#6-usando-docker-compose-convencional)
- [7. Comandos de execução única](#7-comandos-de-execução-única)
- [8. Modelos locais com Ollama](#8-modelos-locais-com-ollama)
- [9. Agentes de execução prolongada e perfis do Compose](#9-agentes-de-execução-prolongada-e-perfis-do-compose)
- [10. Compartilhando um mesmo espaço de trabalho entre agentes](#10-compartilhando-um-mesmo-espaço-de-trabalho-entre-agentes)
- [11. UID/GID e propriedade de arquivos](#11-uidgid-e-propriedade-de-arquivos)
- [12. Limites de recursos](#12-limites-de-recursos)
- [13. Mapa de modelos](#13-mapa-de-modelos)
- [14. Resolução de problemas](#14-resolução-de-problemas)
- [15. Ideias para endurecimento de segurança](#15-ideias-para-endurecimento-de-segurança)

## 1. A ideia

Agentes de codificação de IA são poderosos e obedientes. Isso é útil, mas também
significa que um prompt ruim, uma dependência comprometida ou uma injeção de
prompt podem fazer o agente executar exatamente a ação errada muito rapidamente.

Executar um agente diretamente no seu laptop ou VPS geralmente lhe dá o mesmo
acesso ao sistema de arquivos que seu usuário tem:

- seu diretório inicial real;
- chaves SSH;
- credenciais do GitHub;
- configurações de nuvem;
- histórico do shell;
- projetos aleatórios que você não pretendia expor;
- segredos espalhados em dotfiles locais.

O sannux coloca o agente em um contêiner e monta apenas duas pastas explícitas
do host:

- um **espaço de trabalho** montado em `/workspace`;
- um **diretório inicial do agente** montado em `/home/agent`.

O agente ainda pode funcionar como um assistente de codificação normal. Ele pode
ler e editar o projeto em `/workspace`, instalar pacotes dentro do contêiner,
manter seu próprio estado de login em `/home/agent`, executar comandos do shell
e se comunicar com provedores de modelos. Ele apenas não acessa acidentalmente o
seu diretório inicial real do host.

Considere cada modelo como o formato de uma pequena máquina Linux. Cada run
decide qual workspace e qual agent home essa máquina recebe.

## 2. O que isso protege

Este não é um endurecimento de contêiner de máxima segurança. É um isolamento
prático para fluxos de trabalho de codificação por agentes.

**Isso ajuda a proteger contra:**

- o agente excluindo ou modificando arquivos fora do espaço de trabalho montado;
- o agente lendo `~/.ssh`, `~/.aws`, `~/.config/gh`, `.npmrc`, histórico do
  shell ou outras credenciais do host;
- repositórios Git aninhados acidentalmente dentro deste repositório;
- um agente visualizando a autenticação/configuração/histórico de outro agente;
- comandos descontrolados consumindo muita memória ou CPU.

**Isso não protege contra:**

- exfiltração de rede de arquivos dentro do espaço de trabalho montado;
- código malicioso dentro do projeto que você montou intencionalmente;
- imagens base comprometidas ou binários de agente comprometidos;
- vulnerabilidades de escape de kernel/contêiner;
- um modelo tomando decisões ruins dentro do acesso que você concedeu.

A linha de base é: mantenha o agente longe do seu diretório inicial real,
mantenha o estado de cada agente separado e deixe o caminho de risco explícito.

### Por que não Docker Sandboxes (`sbx`)?

[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) é uma boa opção
quando você quer isolamento mais forte para agentes autônomos: ele executa
sandboxes em microVMs, dá a cada sandbox um Docker daemon próprio e adiciona
políticas e tratamento de credenciais ao redor do acesso de rede.

O `sannux` não tenta substituir isso. Ele fica de propósito em templates de
Docker Compose convencional porque o objetivo do projeto é outro:

- os templates são fáceis de inspecionar, copiar para uma VPS e rodar com
  Docker Compose padrão;
- o runtime evita o overhead de uma VM por sandbox mais um Docker daemon
  privado;
- não há login em conta Docker, instalação do `sbx` nem configuração de
  KVM/hypervisor no caminho feliz;
- agent homes, workspaces, portas, ferramentas e config de providers continuam
  explícitos em arquivos que o usuário pode editar.

As duas abordagens também podem ser empilhadas. Você pode usar `sbx` como a
fronteira externa mais forte e ainda rodar workloads Docker/Compose dentro dele
quando o empacotamento repetível em contêiner for útil. Esse é o desenho melhor
para repositórios críticos, runs com muitos secrets ou agentes sem supervisão
que precisam de liberdade ampla. Isso compra mais isolamento, mas também
adiciona outra camada de runtime e mais partes móveis.

Use `sbx`, outro sandbox baseado em microVM ou uma VM remota descartável quando
você precisar de uma fronteira mais forte, especialmente se o agente tiver que
buildar e executar contêineres aninhados com autonomia ampla ou lidar com
credenciais sensíveis. Use `sannux` quando você quiser templates Docker
práticos, auditáveis e fáceis de copiar, e aceitar isolamento normal de
contêiner como a fronteira.

## 3. As duas pastas que importam

Cada modelo requer estes valores de `.env`:

```env
WORKSPACE_PATH=/absolute/path/to/the/project
AGENT_HOME_PATH=/absolute/path/to/this/agent/home
```

Dentro do contêiner, eles se tornam:

```txt
WORKSPACE_PATH  -> /workspace
AGENT_HOME_PATH -> /home/agent
```

Isso é um bind mount: o Docker liga uma pasta real do host a um caminho dentro
do contêiner. Não é uma cópia; se o agente alterar `/workspace`, ele altera a
pasta indicada em `WORKSPACE_PATH` no host.

Use caminhos fora deste repositório.

Recomendado:

```txt
/srv/example-data/workspaces/my-app
/srv/example-data/agent-homes/codex
```

Também funciona para testes locais:

```txt
/home/example/sannux-data/codex/workspace
/home/example/sannux-data/codex/home
```

Evite:

```txt
$HOME/path/to/sannux/templates/codex/workspace
$HOME/path/to/sannux/.agent-home
$HOME
~
/
```

Por que tão rigoroso?

O espaço de trabalho é o que o agente tem permissão para editar. O diretório
inicial do agente é onde a CLI armazena tokens de login, configurações, sessões,
logs, memória e histórico local. Sessões TUI e login manual normalmente usam
uma agent home persistente. Automação com permissões amplas deve preferir uma
agent home efêmera baseada em uma config de template já testada. Se essas
pastas estiverem dentro do repositório, torna-se muito fácil acidentalmente
fazer commit de estado, credenciais, caches ou de um repositório dentro de outro
repositório.

### Troca temporária de workspace

Para testes locais rápidos, você pode rodar o mesmo template contra outro
workspace sem editar `.env` nem criar uma nova cópia do template. Crie a pasta
alvo primeiro, depois sobrescreva apenas `/workspace` naquele comando:

```bash
mkdir -p /tmp/sannux-example-workspace
just compose pi run -v /tmp/sannux-example-workspace:/workspace --rm -it agent
```

Essa sobrescrita vale só para aquele comando: `WORKSPACE_PATH` no `.env` não
muda, e o agente continua usando o mesmo `AGENT_HOME_PATH` persistido para
auth/configuração/estado.

Use isso de propósito. A forma curta `-v host:container` é o bind mount direto
do Docker, então ela passa por fora da proteção `create_host_path: false` do
template e o Docker pode criar um caminho ausente no host. Prefira um caminho
absoluto já existente, e não monte sua home real, `/`, chaves SSH, credenciais
de cloud nem o socket do Docker.

Para um run one-shot, `-v` muitas vezes já basta: aponte `/workspace` e
`/home/agent` para as pastas do host que você quer usar naquele comando.

### Portas de preview por comando

Templates efêmeros de CLI não publicam portas fixas no host por padrão. Se um
agente subir um frontend, backend ou servidor HTTP temporário, publique só a
porta necessária para aquela execução:

```bash
cd templates/codex
docker compose run --rm -p 127.0.0.1:3001:3000 agent
```

Isso mapeia `127.0.0.1:3001` no host Docker para a porta `3000` dentro daquele
contêiner. Escolha qualquer par de portas que faça sentido para o app:

```bash
docker compose run --rm -p 127.0.0.1:8001:8000 agent
docker compose run --rm -p 127.0.0.1::3000 agent  # porta aleatória no host
```

Se você subir uma aplicação dentro do contêiner, faça ela escutar em `0.0.0.0`,
não apenas em `localhost`, para o Docker conseguir encaminhar o tráfego. Em uma
VPS, use `0.0.0.0:PORTA_HOST:PORTA_CONTAINER` apenas quando você realmente
quiser expor a aplicação, e coloque firewall ou proxy reverso na frente.

Templates de estilo daemon, como `remote-dev`, Claude Code `remote-control` e
Hermes `gateway`/`dashboard`, continuam declarando suas próprias portas
persistentes no Compose, porque esses serviços existem para ser endpoints
remotos estáveis.

## 4. Primeira execução com Codex

Os exemplos abaixo usam o Codex porque é fácil de demonstrar. O mesmo layout de
pastas se aplica a todos os modelos.

Na raiz do repositório:

```bash
just init codex
```

Idealmente, edite `templates/codex/.env`:

```env
USER_UID=1000
USER_GID=1000
WORKSPACE_PATH=/srv/example-data/workspaces/my-project
AGENT_HOME_PATH=/srv/example-data/agent-homes/codex
SANNUX_TERM=xterm-256color
SANNUX_COLORTERM=truecolor
# Opcional para quem usa API key:
# OPENAI_API_KEY=sk-...
MEM_LIMIT=4g
CPU_LIMIT=4
```

Crie as pastas no host e preencha defaults seguros em `~/sannux-data` se
`WORKSPACE_PATH` ou `AGENT_HOME_PATH` ficaram vazios:

```bash
just setup codex
```

Valide a configuração do Compose e execute:

```bash
just config codex
just run codex
```

Quem usa API key pode descomentar `OPENAI_API_KEY` em `templates/codex/.env` e
rodar normalmente. Não precisa fazer login no Codex.

Quem usa OAuth/subscription recebe o pedido de login na primeira execução. O
menu de auth tem três opções. Dentro do Docker, use **Sign in with Device
Code**; não use **Sign in with ChatGPT**, porque esse caminho assume um browser
desktop local. O arquivo de autenticação é gravado em:

```txt
${AGENT_HOME_PATH}/.codex/
```

Ao sair, o contêiner é removido porque o comando padrão usa
`docker compose run --rm`. Seu espaço de trabalho e diretório inicial do agente
permanecem no host.

Execute novamente:

```bash
just run codex
```

O contêiner é novo, mas o estado do agente ainda está lá porque
`AGENT_HOME_PATH` foi montado novamente.

## 5. Usando just

O `just` é apenas um wrapper de conveniência para pessoas que clonaram o
repositório inteiro. Ele não faz nada mágico.

Liste as receitas:

```bash
just
```

Crie o `.env` de um modelo a partir de `.env.example`:

```bash
just init codex
```

Rode o setup de um modelo quando ele tiver um helper específico:

```bash
just setup remote-dev
```

Renderize e valide a configuração do Compose:

```bash
just config codex
```

Construa um modelo:

```bash
just build codex
```

Reconstrua sem cache:

```bash
just rebuild codex
```

Execute o agente interativamente:

```bash
just run codex
```

Abra um shell dentro da mesma imagem de contêiner:

```bash
just shell codex
```

Abra um shell root para depurar a imagem:

```bash
just root-shell codex
```

Trate alterações feitas no `root-shell` como descartáveis. Se você instalar
pacotes ou mudar arquivos fora dos volumes montados, essas alterações somem com
o contêiner efêmero; faça mudanças reais no Dockerfile e reconstrua.

O ciclo do dia a dia é propositalmente pequeno. Exemplo com Claude Code:

```bash
just setup claude-code      # cria .env e pastas seguras no host
just run claude-code        # inicia um contêiner interativo novo
```

Troque `claude-code` por qualquer modelo listado em `just templates`.

Para adicionar mais ferramentas a uma imagem, edite o `Dockerfile` daquele
modelo e reconstrua. Por exemplo:

```bash
just rebuild claude-code
```

Pare e remova contêineres/redes/volumes do Compose para um modelo:

```bash
just down codex
```

Para serviços daemon, como Claude Code Remote Control, gateway do Hermes,
dashboard do Hermes ou o serviço Remote SSH:

```bash
just up claude-code remote-control
just up hermes gateway
just up hermes dashboard
just up remote-dev ssh
just logs claude-code remote-control
just logs hermes gateway
just logs hermes dashboard
just logs remote-dev ssh
just ps claude-code
just ps hermes
just ps remote-dev
just down claude-code
just down hermes
just down remote-dev
```

Se uma receita disser que o arquivo `.env` está ausente, crie-o primeiro:

```bash
just init codex
```

### Apps com Remote SSH

Use `remote-dev` quando o app fica no seu computador, mas precisa de um único
ambiente Linux via SSH para rodar comandos e instalar seu servidor remoto. Isso
serve para apps externos sem fluxo de CLI próprio ou com integração Remote SSH,
como Claude Desktop/Claude Code, Codex App, Antigravity, VS Code Remote SSH e
ferramentas parecidas.

Pense nele como um servidor SSH remoto persistente: cômodo para isolar apps de
terceiros, mas não como um template efêmero para vários agentes paralelos. Até
dá para criar vários ambientes `remote-dev`, cada um com suas próprias portas,
homes e workspaces, mas isso consome mais recursos e fica mais chato de
gerenciar. Para agentes efêmeros de CLI, prefira os templates de CLI com
`docker compose run --rm agent`.

Diferente dos templates de CLI, o `remote-dev` é daemon-first: o serviço
principal é o `ssh` de longa duração no Compose profile `daemon`. O serviço
`agent` é só um shell auxiliar não-root para diagnóstico ou trabalho avulso.

O caminho mais simples:

```bash
just setup remote-dev
```

Esse comando cria a chave SSH dedicada, escreve a entrada `sannux-remote-dev`
no `~/.ssh/config` com o usuário `agent`, prepara o diretório runtime do
app-server do Codex, monta a imagem e sobe o serviço SSH.

Depois conecte o app em:

```txt
sannux-remote-dev
```

E abra a pasta:

```txt
/workspace
```

A home persistente fica no host, mas `~/.codex/app-server-control` roda em um
tmpfs dentro do contêiner. `tmpfs` é uma pasta temporária em memória: boa para
sockets e arquivos runtime, ruim para estado que precisa sobreviver. Isso evita
o caso do Docker Desktop no macOS rejeitar permissões em Unix sockets usados
pelo Codex App via SSH.

O app roda localmente. O servidor remoto dele, os comandos, o cache e o acesso
ao projeto rodam dentro do contêiner.

## 6. Usando Docker Compose convencional

Se você copiou apenas uma pasta de modelo para um VPS, use o Docker Compose
diretamente.

Exemplo com `templates/codex`:

```bash
cd templates/codex
install -m 0600 .env.example .env
mkdir -p /srv/example-data/workspaces/my-project
mkdir -p /srv/example-data/agent-homes/codex
# edit .env
docker compose build
docker compose run --rm agent
```

Publique uma porta de preview em uma sessão interativa com `run`:

```bash
docker compose run --rm -p 127.0.0.1:3001:3000 agent
```

Use qualquer par de portas necessário para aquela sessão. Por exemplo,
`-p 127.0.0.1:8001:8000` mapeia a porta `8001` do host para a porta `8000` do
contêiner.

Acesso shell equivalente:

```bash
docker compose run --rm --entrypoint bash agent
```

Acesso shell root equivalente para depuração:

```bash
docker compose run --rm --user root --entrypoint bash agent
```

Limpe o projeto do Compose:

```bash
docker compose down -v
```

Isso não deleta `WORKSPACE_PATH` nem `AGENT_HOME_PATH`, pois ambos são montagens
de host (bind mounts).

## 7. Comandos de execução única

Interfaces de terminal interativas são boas para humanos. Para automação, o
stdin geralmente é mais fácil.
Os exemplos de baixo nível com `just run` e `docker compose run` abaixo usam o
`AGENT_HOME_PATH` configurado no template. Isso é conveniente, mas em automação
YOLO sem operador também significa que o comando pode ler e escrever na mesma
autenticação, sessões, logs, caches e histórico da sua TUI.

Para `codex-ollama`, use a home persistente quando compartilhar o estado da TUI
for aceitável:

```bash
cd templates/codex-ollama
echo "Summarize the mounted project and list risky files." \
  | docker compose run --rm -T agent exec - --ephemeral --yolo
```

Use uma home temporária quando você quiser expor só a config do Codex que aceita
usar naquele run:

```bash
cd templates/codex-ollama
mkdir -p /srv/example-data/tmp/workspace-1 /srv/example-data/tmp/home-1
test -d /srv/example-data/agent-homes/codex-ollama/.codex

echo "Summarize the temporary workspace." \
  | docker compose run \
    -v /srv/example-data/tmp/workspace-1:/workspace \
    -v /srv/example-data/tmp/home-1:/home/agent \
    -v /srv/example-data/agent-homes/codex-ollama/.codex:/home/agent/.codex \
    --rm -T agent exec - --ephemeral --yolo
```

Docker `-v` pode criar pastas ausentes no host, e `.codex` pode conter
autenticação ou API state. Monte só o que você aceita expor para aquele run.

Codex a partir da raiz do repositório:

```bash
printf '%s\n' "Summarize the mounted project and list risky files." | \
  just compose codex run --rm -T agent exec \
    --ephemeral --dangerously-bypass-approvals-and-sandbox -
```

Codex a partir da pasta do modelo:

```bash
cd templates/codex
printf '%s\n' "Summarize the mounted project and list risky files." | \
  docker compose run --rm -T agent exec \
    --ephemeral --dangerously-bypass-approvals-and-sandbox -
```

Gemini a partir da raiz do repositório:

```bash
just run gemini -p "summarize the mounted project"
```

No Gemini, o stdin é anexado ao prompt do `-p`. Use apenas `-p`, a menos que
você queira juntar intencionalmente o contexto do stdin com o prompt.

OpenCode a partir da raiz do repositório:

```bash
just run opencode run "Summarize the mounted project and list risky files."
```

O OpenCode usa `opencode run [message..]` para automação não-interativa.
Configure `permission` em `opencode.json` quando um run deve pedir aprovação ou
negar leituras, edições, comandos shell ou acesso a diretórios externos. Runs
reais autenticados com OpenCode ainda não foram testados; PRs com notas
verificadas por provider são bem-vindos. Para tarefas de escrita sem operador,
o `opencode run --help` local também expõe `--dangerously-skip-permissions`;
mantenha regras `deny` explícitas para qualquer coisa que o run nunca deve fazer.

Pi a partir da raiz do repositório:

```bash
echo "Summarize the mounted project and list risky files." | just run pi -p
```

Claude Code com autenticação Anthropic a partir da pasta do modelo, usando a
home persistente:

```bash
cd templates/claude-code
echo "Summarize the mounted project and list risky files." \
  | docker compose run --rm -T agent \
    --dangerously-skip-permissions --no-session-persistence -p -
```

Use uma home temporária quando quiser uma `/home/agent` nova, reaproveitando os
arquivos de estado do Claude preparados pelo `just setup claude-code`:

```bash
template_dir=/srv/sannux/templates/claude-code
mkdir -p /srv/example-data/tmp/workspace-1
persistent_home=/srv/example-data/agent-homes/claude-code
tmp_home="$(mktemp -d)"
trap 'rm -rf "$tmp_home"' EXIT
test -d "$persistent_home/.claude"
test -f "$persistent_home/.claude.json"
cp -R "$persistent_home/.claude" "$tmp_home/.claude"
cp -p "$persistent_home/.claude.json" "$tmp_home/.claude.json"

echo "Summarize the temporary workspace." \
  | docker compose --project-directory "$template_dir" run \
    -v /srv/example-data/tmp/workspace-1:/workspace \
    -v "$tmp_home:/home/agent" \
    --rm -T agent \
    --dangerously-skip-permissions --no-session-persistence -p -
```

Com autenticação real do Claude Code, `.claude` e `.claude.json` podem conter
login, projetos confiáveis, hooks, config de MCP e outros estados privados.
Copie esses caminhos apenas para runs onde você aceita expor esse estado.

Claude Code com Ollama a partir da pasta do modelo, usando a home persistente:

```bash
cd templates/claude-ollama
echo "Summarize the mounted project and list risky files." \
  | docker compose run --rm -T agent \
    --dangerously-skip-permissions --no-session-persistence -p -
```

Use uma home temporária quando quiser uma `/home/agent` nova, reaproveitando os
arquivos de estado do Claude preparados pelo `just setup claude-ollama`:

```bash
template_dir=/srv/sannux/templates/claude-ollama
mkdir -p /srv/example-data/tmp/workspace-1
persistent_home=/srv/example-data/agent-homes/claude-ollama
tmp_home="$(mktemp -d)"
trap 'rm -rf "$tmp_home"' EXIT
test -d "$persistent_home/.claude"
test -f "$persistent_home/.claude.json"
cp -R "$persistent_home/.claude" "$tmp_home/.claude"
cp -p "$persistent_home/.claude.json" "$tmp_home/.claude.json"

echo "Summarize the temporary workspace." \
  | docker compose --project-directory "$template_dir" run \
    -v /srv/example-data/tmp/workspace-1:/workspace \
    -v "$tmp_home:/home/agent" \
    --rm -T agent \
    --dangerously-skip-permissions --no-session-persistence -p -
```

No Claude/Ollama, você também pode trocar o workspace para um comando:

```bash
cd templates/claude-ollama
test -d "$HOME/Projects/example-project"
echo "Just a test. Create a file called test.txt in the current directory. Add the current timestamp inside it in ISO 8601/RFC 3339 format, including timezone." \
  | docker compose run \
    -v "$HOME/Projects/example-project:/workspace" \
    --rm -T agent \
    --dangerously-skip-permissions \
    --no-session-persistence \
    -p -
```

Esse comando ainda usa a agent home persistente do `.env`; apenas `/workspace`
é substituído naquele run.

O detalhe importante é usar `-T` com o Docker Compose ao encadear (pipe) a
entrada. Ele desativa a alocação de TTY para aquela execução, fazendo com que o
stdin se comporte como uma automação normal.
Depois que o comando imprime a resposta, o contêiner `--rm` encerra e é
removido.

## 8. Modelos locais com Ollama

Os modelos `*-ollama` dividem a pilha em duas partes:

- o **ambiente do agente** executa dentro do Docker;
- o **modelo** executa no Ollama em outro lugar.

Isso é útil porque o ambiente traz ferramentas de terminal/arquivo, enquanto o
Ollama serve um modelo local ou de pesos abertos.

### Na mesma máquina do Docker

Se o Ollama estiver rodando no mesmo host onde o Docker está rodando:

```env
OLLAMA_BASE_URL=http://host.docker.internal:11434/v1
```

Para modelos compatíveis com Claude:

```env
ANTHROPIC_BASE_URL=http://host.docker.internal:11434
```

### Outra máquina na rede LAN

Se o Ollama estiver rodando em outra máquina:

```env
OLLAMA_BASE_URL=http://192.0.2.50:11434/v1
```

Para modelos compatíveis com Claude:

```env
ANTHROPIC_BASE_URL=http://192.0.2.50:11434
```

Use o IP real da máquina que executa o Ollama.

### Catálogo de modelos Codex para Ollama

A CLI do Codex espera metadados do modelo: janela de contexto, suporte a
raciocínio, suporte a ferramentas e flags de comportamento relacionadas. Os
nomes dos modelos locais do Ollama não estão no catálogo integrado do Codex,
então `templates/codex-ollama/` inclui:

```txt
model_catalog.json
```

O arquivo compose monta isso como somente leitura em:

```txt
/opt/sannux/model_catalog.json
```

O mesmo template também inclui `codex-config.toml.template`. Rode:

```bash
just setup codex-ollama
```

para renderizar `${AGENT_HOME_PATH}/.codex/config.toml`. O Codex carrega essa
configuração tanto no modo interativo quanto no `codex exec`, então comandos de
execução única podem ficar curtos.

Se você alterar:

```env
CODEX_MODEL=local-model:8b
```

também atualize o `slug` correspondente em `model_catalog.json`.

Se o catálogo disser que o modelo tem uma janela de contexto maior do que o
Ollama realmente oferece, o Codex planejará em torno de uma janela de contexto
que não existe de fato. Mantenha o catálogo preciso.

## 9. Agentes de execução prolongada e perfis do Compose

A maioria dos modelos é interativa:

```bash
docker compose run --rm agent
```

Ao sair da CLI, o contêiner para e é removido. Isso é perfeito para sessões de
codificação.

Alguns templates também possuem um modo real de funcionamento 24/7. O Claude
Code pode rodar Remote Control em segundo plano, o Hermes pode manter mensagens,
webhooks e tarefas agendadas ativos através do processo `gateway`, o Hermes pode
rodar seu dashboard no navegador, e o `remote-dev` pode manter um alvo SSH
rodando. Como esses serviços podem receber comandos enquanto você está longe,
trate URLs de acesso, chaves SSH, listas de usuários permitidos em mensageria,
acesso ao dashboard e aprovações de comando como parte do deploy, não como
detalhe opcional.

Esses serviços ficam atrás de um perfil do Compose:

```yaml
profiles: ['daemon']
```

Os perfis são grupos opcionais de serviços. O Docker Compose não os inicia a
menos que você solicite explicitamente.

Inicie o Claude Code Remote Control:

```bash
just up claude-code remote-control
```

O serviço `remote-control` roda `claude -n main-session --remote-control` em
segundo plano. Ele é útil em fluxos de VPS/celular quando você quer uma URL
persistente de sessão do Claude Code. A imagem também inclui `tmux`, para que
sessões Claude no estilo gerente possam iniciar e inspecionar sessões filhas em
paralelo dentro do mesmo sandbox.

Inicie o gateway do Hermes:

```bash
just up hermes gateway
```

Inicie o dashboard do Hermes:

```bash
just up hermes dashboard
```

Inicie o SSH do remote-dev:

```bash
just up remote-dev ssh
```

O serviço `remote-control` do Claude Code, gateway/dashboard do Hermes e o
serviço SSH do remote-dev publicam suas portas de preview configuradas para
daemon. Isso permite que apps iniciados por sessões de agente via
navegador/celular, o dashboard do Hermes ou clientes Remote SSH continuem
acessíveis por portas estáveis no host. Sessões comuns com `run --rm` continuam
sem porta publicada, a menos que você adicione `-p` naquele comando específico.

O dashboard do Hermes faz bind em `127.0.0.1` no host por padrão. Trate-o como
sensível porque ele pode gerenciar config e API keys do Hermes.

Sem o `just`, para Claude Code:

```bash
cd templates/claude-code
docker compose --profile daemon up -d remote-control
```

Sem o `just`, para Hermes:

```bash
cd templates/hermes
docker compose --profile daemon up -d gateway
docker compose --profile daemon up -d dashboard
```

Sem o `just`, para remote-dev:

```bash
cd templates/remote-dev
docker compose --profile daemon up -d ssh
```

Verifique:

```bash
just ps claude-code
just logs claude-code remote-control
just ps hermes
just logs hermes gateway
just logs hermes dashboard
just ps remote-dev
just logs remote-dev ssh
```

Pare-o:

```bash
just down claude-code
just down hermes
just down remote-dev
```

Sem o `just`, para Claude Code:

```bash
cd templates/claude-code
docker compose stop remote-control
```

Sem o `just`, para Hermes:

```bash
cd templates/hermes
docker compose stop gateway
docker compose stop dashboard
```

Sem o `just`, para remote-dev:

```bash
cd templates/remote-dev
docker compose stop ssh
```

Use o modelo mental:

```txt
run --rm agent       -> sessão temporária; encerra ao sair da TUI
run --rm agent ...   -> comando de execução única; encerra após a resposta
--profile daemon up  -> serviço em segundo plano que deve permanecer ativo
```

O dashboard do Hermes também é um serviço no perfil daemon. Ele roda o dashboard
upstream compilado na porta `9119` dentro do contêiner e publica em
`${PORT_BIND_ADDRESS}:${HOST_PORT_DASHBOARD}` no host.

## 10. Compartilhando um mesmo espaço de trabalho entre agentes

Você pode apontar vários agentes para o mesmo `WORKSPACE_PATH`.

Exemplo:

```env
# templates/codex/.env
WORKSPACE_PATH=/srv/example-data/workspaces/my-app
AGENT_HOME_PATH=/srv/example-data/agent-homes/codex-my-app
```

```env
# templates/gemini/.env
WORKSPACE_PATH=/srv/example-data/workspaces/my-app
AGENT_HOME_PATH=/srv/example-data/agent-homes/gemini-my-app
```

Isso permite que dois agentes trabalhem no mesmo projeto enquanto mantêm seus
próprios tokens de login, configurações, logs, memória e sessões separados.

Esta é a estrutura recomendada:

```txt
mesmo espaço de trabalho, diretórios iniciais separados
```

Evite:

```txt
mesmo espaço de trabalho, mesmo diretório inicial do agente
```

Diretórios iniciais separados limitam vazamentos acidentais entre agentes. Se um
ambiente armazenar algo incomum em seu diretório inicial, o outro agente não
herdará isso.

Um aviso prático: dois agentes editando os mesmos arquivos ao mesmo tempo ainda
podem causar conflitos. Use Git, commits, branches ou limites de tarefas claros
ao realizar trabalho em paralelo.

## 11. UID/GID e propriedade de arquivos

Cada modelo cria um usuário sem privilégios de root chamado `agent`. Estes
valores controlam a identidade numérica desse usuário:

```env
USER_UID=1000
USER_GID=1000
```

No Linux, isso faz diferença. Arquivos criados em uma montagem de host (bind
mount) mantêm a propriedade numérica. Defina estes valores para o seu usuário do
host:

```bash
id -u
id -g
```

Em muitos servidores Linux, você obterá:

```env
USER_UID=1000
USER_GID=1000
```

No macOS, os valores podem parecer diferentes:

```env
USER_UID=501
USER_GID=20
```

O Docker Desktop traduz muita disso para você no macOS, então a propriedade de
arquivos é menos problemática lá. Ainda assim, manter os números reais no `.env`
torna os exemplos mais portáteis e evita surpresas ao mover o modelo para o
Linux.

Se você alterar `USER_UID` ou `USER_GID`, reconstrua a imagem:

```bash
just rebuild codex
```

ou:

```bash
docker compose build --no-cache
```

## 12. Limites de recursos

Cada modelo expõe:

```env
MEM_LIMIT=4g
CPU_LIMIT=4
```

E os arquivos compose incluem:

```yaml
mem_limit: ${MEM_LIMIT:-4g}
cpus: ${CPU_LIMIT:-4}
pids_limit: 512
```

Estes não são uma fronteira de segurança. Eles servem como proteção contra
acidentes:

- loops descontrolados;
- instalações de dependências que explodem em tamanho/consumo;
- comandos de build usando muita memória;
- muitos processos filhos.

Em um VPS, ajuste-os conforme o tamanho da máquina. No Docker Desktop, eles
ainda ajudam, mas o limite real também depende da alocação de recursos da VM do
Docker Desktop.

O Hermes vem com mais memória por padrão porque a imagem e os extras opcionais
são mais pesados:

```env
MEM_LIMIT=8g
CPU_LIMIT=4
```

## 13. Mapa de modelos

Use isto como tabela de escolha rápida.

### `codex`

Use quando quiser a CLI do OpenAI Codex com autenticação da OpenAI.

Primeira execução:

```bash
just setup codex
just run codex
```

Login por device code:

```bash
cd templates/codex
docker compose run --rm agent login --device-auth
```

Quem usa API key pode pular esse login definindo `OPENAI_API_KEY` em
`templates/codex/.env`, ou escolhendo a opção de API key no prompt do Codex.

Esse fluxo mostra um código para você autorizar em outro navegador. É o caminho
mais simples quando a VPS não tem interface gráfica.

Execução única:

```bash
printf '%s\n' "Review this project." | \
  just compose codex run --rm -T agent exec \
    --ephemeral --dangerously-bypass-approvals-and-sandbox -
```

### `codex-ollama`

Use quando quiser o ambiente do Codex com um modelo servido pelo Ollama.

Valores importantes de `.env`:

```env
OLLAMA_BASE_URL=http://192.0.2.50:11434/v1
CODEX_MODEL=local-model:8b
```

Rode `just setup codex-ollama` depois de editar `.env`; isso escreve a config
persistida usada pela TUI e pelo `codex exec`. Para runs one-shot, use a mesma
agent home ou monte uma `/home/agent` temporária com apenas a pasta `.codex` que
você aceita expor.

Se o modelo mudar, atualize o `model_catalog.json`.
Esse arquivo diz ao Codex quais recursos aquele modelo local tem. O `slug` deve
bater com o nome do modelo usado em `CODEX_MODEL`.

### `claude-code`

Use quando quiser o Claude Code com autenticação da Anthropic.
Ele também tem um serviço Remote Control opcional para fluxos persistentes em
VPS/celular.

Primeiro setup:

```bash
just setup claude-code
just run claude-code
```

O Claude armazena autenticação e config na agent home, não na sua home real do
host. TUI e Remote Control compartilham o mesmo `WORKSPACE_PATH` e
`AGENT_HOME_PATH`. Para runs one-shot efêmeras, copie apenas `.claude` e
`.claude.json` para a home temporária quando você aceitar expor esse estado do
Claude.

Remote Control:

```bash
just up claude-code remote-control
just logs claude-code remote-control
just down claude-code
```

### `claude-ollama`

Use quando quiser o ambiente do Claude Code apontado para um servidor Ollama que
expõe uma API compatível com a Anthropic.

Primeiro setup:

```bash
just setup claude-ollama
just run claude-ollama
```

Valores importantes de `.env`:

```env
ANTHROPIC_BASE_URL=http://192.0.2.50:11434
ANTHROPIC_AUTH_TOKEN=ollama
ANTHROPIC_API_KEY=
ANTHROPIC_MODEL=example-ollama-model
```

Execução única:

```bash
cd templates/claude-ollama
echo "Review this project." \
  | docker compose run --rm -T agent \
    --dangerously-skip-permissions --no-session-persistence -p -
```

### `gemini`

Use quando quiser a CLI do Google Gemini.

Opções de autenticação:

- `GEMINI_API_KEY`;
- OAuth do Google armazenado no diretório inicial do agente;
- configuração do Vertex AI.

Setup inicial:

```bash
just setup gemini
just run gemini
```

Modo de prompt:

```bash
just run gemini -p "summarize the mounted project"
```

Para tarefas one-shot de escrita, use `--yolo` ou `--approval-mode yolo`
explicitamente. Sem isso, o Gemini pode tentar editar por bastante tempo e só
depois parar porque o run não-interativo não consegue conceder aprovação.

### `hermes`

Use quando quiser o Hermes Agent, especialmente para mensagens/webhooks/tarefas
agendadas.

O Hermes pode chamar outras CLIs de agente quando você as adiciona na imagem,
mas este template não embute Codex, Claude Code, Gemini, Pi, opencode nem toda
ferramenta possível de delegação. Instale o que precisar em
`templates/hermes/Dockerfile`, reconstrua e mantenha o auth limitado à agent
home do Hermes ou ao `.env` deste template.

Primeira configuração:

```bash
just setup hermes
just run hermes setup
just run hermes
```

Gateway 24/7:

```bash
just up hermes gateway
just logs hermes gateway
just down hermes
```

Dashboard:

```bash
just up hermes dashboard
just logs hermes dashboard
just down hermes
```

### `opencode`

Use quando quiser a CLI independente de modelo do opencode.

Primeira execução:

```bash
just setup opencode
just run opencode
```

Login do provedor:

```bash
just run opencode auth login
```

One-shot:

```bash
just run opencode run "Summarize the mounted project."
```

### `pi`

Use quando quiser o Pi Coding Agent.

Primeira execução:

```bash
just setup pi
just run pi
```

Execução única / modo de impressão:

```bash
echo "Summarize the mounted project." | just run pi -p
```

O Pi também suporta configuração de modelo local através de sua própria
configuração persistente em:

```txt
${AGENT_HOME_PATH}/.pi/agent/
```

O Pi não fornece serviço daemon neste template. Para runs não interativos, use
`-p` / `--print`; use `--tools read,grep,find,ls` para revisões somente leitura,
ou `--no-session` quando uma execução one-shot não deve gravar arquivo de
sessão.

### `remote-dev`

Use quando quiser um servidor SSH remoto único para apps locais com suporte a
Remote SSH, em vez de uma CLI de agente pré-instalada. É o encaixe para Claude
Desktop/Claude Code, Codex App, Antigravity, VS Code Remote SSH e ferramentas
parecidas que precisam instalar um servidor remoto dentro de um Linux isolado.

Ele foi pensado como um ambiente persistente para apps externos, não como um
template efêmero para vários agentes paralelos. Se a ideia é disparar agentes
de CLI sob demanda, use os templates de CLI com
`docker compose run --rm agent`.

O serviço `ssh` de longa duração é o modo real do `remote-dev`. O serviço
`agent` é só um shell não-root e não é um harness one-shot específico de
provedor.

Setup em um comando:

```bash
just setup remote-dev
```

Depois conecte o app em:

```txt
sannux-remote-dev
```

O socket SSH do app-server do Codex fica em `~/.codex/app-server-control`; o
`remote-dev` deixa esse runtime em tmpfs dentro do contêiner e mantém o resto da
home do agente persistente. O app continua rodando no seu computador; o
servidor remoto dele roda dentro do contêiner.

## 14. Resolução de problemas

### `WORKSPACE_PATH está sem valor`

O Docker Compose não recebeu um caminho de workspace. Alguns templates, como
`codex`, `codex-ollama`, `claude-code`, `claude-ollama` e `remote-dev`,
conseguem preencher um fallback seguro quando você roda o script de setup
antes.

Correção:

```bash
install -m 0600 .env.example .env
# edite .env, ou rode o script de setup do template quando documentado
```

### `caminho de origem do bind não existe`

Os arquivos compose usam intencionalmente:

```yaml
create_host_path: false
```

Isso impede que o Docker crie silenciosamente a pasta errada para você.
Em outras palavras: se você errou o caminho, o comando falha cedo em vez de
criar uma pasta vazia e fazer o agente trabalhar no lugar errado.

Crie as pastas você mesmo:

```bash
mkdir -p /srv/example-data/workspaces/my-project
mkdir -p /srv/example-data/agent-homes/codex
```

### Arquivos são de propriedade do usuário errado no Linux

Defina `USER_UID` e `USER_GID` para o seu usuário do host e reconstrua:

```bash
id -u
id -g
just rebuild codex
```

### Cores da interface de terminal (TUI) estão erradas

Os modelos definem:

```env
SANNUX_TERM=xterm-256color
SANNUX_COLORTERM=truecolor
```

Se uma CLI ainda recusar as cores, tente:

```env
SANNUX_FORCE_COLOR=1
```

Isso pode tornar a saída encadeada (pipe) mais verbosa, por isso ela vem
comentada por padrão.

### URL do Ollama não funciona

Use `/v1` para clientes compatíveis com OpenAI:

```env
OLLAMA_BASE_URL=http://192.0.2.50:11434/v1
```

Não use `/v1` para configurações do Claude Code compatíveis com Anthropic:

```env
ANTHROPIC_BASE_URL=http://192.0.2.50:11434
```

`host.docker.internal` é para o host do Docker. Se o Ollama estiver rodando em
outra máquina, use o IP LAN dessa máquina.

### O agente não consegue ver meu projeto

Dentro do contêiner, o projeto está sempre em:

```txt
/workspace
```

Verifique o que você montou:

```bash
just shell codex
pwd
ls -la /workspace
```

### Fechei o terminal e o agente parou

Isso é esperado para:

```bash
docker compose run --rm agent
```

Para automação 24/7 do Hermes, use:

```bash
just up hermes gateway
```

### Posso montar meu diretório inicial real?

Tecnicamente sim. Não faça isso para este projeto.

O objetivo destes modelos é evitar conceder acidentalmente a um agente de
codificação autônomo acesso ao seu diretório inicial real.

## 15. Ideias para endurecimento de segurança

Os modelos base são intencionalmente usáveis antes de se tornarem paranóicos.
Bons próximos passos para ambientes mais rigorosos:

- listagem de permissão para saída de rede;
- `cap_drop: [ALL]`;
- sistema de raiz somente leitura mais montagens graváveis explícitas;
- perfis customizados de seccomp/AppArmor;
- redes Docker separadas por agente;
- sem chaves de provedor no `.env`, apenas tokens de curta duração;
- fixação de imagem e varredura de vulnerabilidades;
- usuários Linux separados no host para diferentes famílias de agentes;
- microVMs quando o isolamento de contêiner não for suficiente.

Não adicione tudo isso cegamente. Cada camada tem um custo de usabilidade. A
posição padrão do projeto é priorizar o isolamento prático primeiro, depois
controles mais rigorosos onde o risco justifique o atrito.

## Licença

[MIT](./LICENSE).
