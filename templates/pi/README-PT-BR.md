# pi

[Pi Coding Agent](https://pi.dev/docs/latest/quickstart) rodando em um contêiner
Docker `debian-slim`.

Este template é pequeno de propósito: configure um workspace persistente e um
home persistente do Pi, autentique uma vez, e depois escolha se cada execução
vai ser interativa, one-shot persistente ou one-shot efêmera.

Runs reais autenticados com Pi não foram testados nesta passada; o contrato de
CLI abaixo vem da documentação oficial do Pi e do comportamento local de
`pi --help`.

## Example Vídeo (PT-BR 🇧🇷)

Example using `codex-ollama` (in Brazilian Portuguese).

[![Agentes de IA Seguros no Docker](https://i3.ytimg.com/vi/wqe0VU5L5aU/maxresdefault.jpg)](https://youtu.be/wqe0VU5L5aU)

- [youtu.be/wqe0VU5L5aU](https://youtu.be/wqe0VU5L5aU)

## O que este template entrega

- `Dockerfile`: CLI do Pi mais ferramentas comuns de desenvolvimento em Linux.
- `compose.yml`: serviço Docker Compose que monta seu projeto em `/workspace` e
  o home do agente em `/home/agent`.
- `setup-host.sh`: cria as pastas do host, escreve defaults seguros no `.env` e
  prepara o diretório de configuração persistida do Pi.

O Pi é instalado pelo pacote npm `@earendil-works/pi-coding-agent`.

## Setup

Copie o arquivo de ambiente:

```bash
install -m 0600 .env.example .env
```

O ideal é editar estes valores para deixar workspace e agent home explícitos:

```env
WORKSPACE_PATH=/srv/example-data/workspaces/my-project
AGENT_HOME_PATH=/srv/example-data/agent-homes/pi
```

Se `WORKSPACE_PATH` e `AGENT_HOME_PATH` ficarem vazios, o `setup-host.sh` usa
este fallback:

```txt
~/sannux-data/workspaces/pi
~/sannux-data/agent-homes/pi
```

Crie as pastas no host e preencha valores ausentes no `.env`:

```bash
./setup-host.sh
```

Inicie e teste a TUI uma vez:

```bash
docker compose run --rm agent
```

A partir da raiz do repositório, o mesmo fluxo é:

```bash
just setup pi
just run pi
```

## Cenários

### 1. Template

O template é o ambiente específico do harness: `pi` significa Pi Coding Agent
rodando com seu próprio workspace e seu próprio agent home isolado.

Outros templates seguem a mesma ideia para outros harnesses, como Codex, Claude,
Gemini, Hermes ou opencode.

### 2. Config inicial persistente

`.env` mais `setup-host.sh` criam o primeiro agent home funcional.

Autentique o Pi de uma destas formas:

- defina chaves de provider como `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`,
  `GEMINI_API_KEY` ou `OPENROUTER_API_KEY` no `.env`;
- rode a TUI com `docker compose run --rm agent` e use `/login`;
- passe uma chave pontual com `--api-key` quando isso for aceitável.

A documentação do Pi diz que login por assinatura e login por chave salvam
estado em `~/.pi/agent`. Com este template, `PI_CODING_AGENT_DIR` fica em:

```txt
/home/agent/.pi/agent
```

No host, isso vira:

```txt
${AGENT_HOME_PATH}/.pi/agent/
```

Espere encontrar estado privado nesse diretório, como `auth.json`,
`settings.json`, `models.json`, `sessions/`, `git/`, `npm/`, extensões, skills,
prompt templates, temas, pacotes instalados, logs e outros dados de runtime.

### 3. TUI persistente

Use isto para trabalho interativo normal:

```bash
docker compose run --rm agent
```

A partir da raiz do repositório:

```bash
just run pi
```

Esse run fica ativo até você sair do Pi. Ele usa o workspace persistente e o
agent home persistente configurados no `.env`.

O Pi carrega arquivos de contexto no startup a partir do diretório global do Pi,
dos diretórios pais e do workspace atual. Instruções de projeto podem ficar em
`/workspace/AGENTS.md` ou `/workspace/CLAUDE.md`; instruções globais podem ficar
em `${AGENT_HOME_PATH}/.pi/agent/AGENTS.md`.

### 4. Daemon persistente

Este template não fornece serviço daemon do Pi.

A documentação oficial da CLI do Pi lista modo interativo, modo print, modo
JSON, modo RPC e exportação HTML. Ela não documenta um daemon de longa duração
com portas estáveis, logs e semântica de desligamento. Se um profile de daemon
for adicionado depois, documente aqui portas, auth, logs e fluxo de parada.

### 5. One-shot com home persistente

Use o modo print quando compartilhar o mesmo agent home for aceitável:

```bash
docker compose run --rm -T agent -p "Summarize the mounted project."
```

Com stdin encadeado:

```bash
cat README.md | docker compose run --rm -T agent -p "Summarize this file."
```

A partir da raiz do repositório:

```bash
echo "Summarize the mounted project." | just run pi -p
```

A documentação do Pi descreve `-p` / `--print` como modo print: o Pi imprime a
resposta e sai. Nesse modo, stdin encadeado por pipe é mesclado no prompt
inicial.

Para uma revisão somente leitura, permita só ferramentas de leitura:

```bash
docker compose run --rm -T agent \
  --tools read,grep,find,ls \
  -p "Review the code and list risky files."
```

O Pi intencionalmente não tem popups de permissão embutidos. As ferramentas
padrão podem ler, escrever, editar e rodar shell dentro do workspace montado.
Para runs desacompanhados, prefira um workspace dedicado, um checkpoint no git,
`--tools` explícito e um home do contêiner que exponha só o estado necessário
para aquele run.

Isso é simples, mas o run consegue ler e escrever todo o `AGENT_HOME_PATH`
persistente: auth, settings, sessões, pacotes, extensões, skills, prompts,
temas, logs e outros estados privados de runtime.

### 6. One-shot com home efêmera

Use isto quando quiser um `/home/agent` novo para um único comando.

Com chaves de provider no `.env`, um home temporário vazio deve bastar:

```bash
template_dir=/srv/example/templates/pi
tmp_workspace=/srv/example-data/tmp/workspace-1
tmp_home="$(mktemp -d)"
trap 'rm -rf "$tmp_home"' EXIT

mkdir -p "$tmp_workspace"
mkdir -p "$tmp_home/.pi/agent"

docker compose --project-directory "$template_dir" run \
  -v "$tmp_workspace:/workspace" \
  -v "$tmp_home:/home/agent" \
  --rm -T agent \
  --no-session \
  --tools read,grep,find,ls \
  -p "Summarize the mounted project."
```

Use `--no-session` quando o comando não deve salvar arquivo de sessão. Isso é
separado do home efêmero no Docker: o home temporário controla qual estado de
auth/config/pacotes do Pi é exposto, e `--no-session` controla se o Pi escreve
uma sessão.

Se você depende de `/login`, `models.json` customizado, pacotes instalados,
extensões, skills, prompts, temas ou contexto global do home persistente, copie
somente o estado que você aceita expor ao run:

```bash
persistent_home=/srv/example-data/agent-homes/pi
test -d "$persistent_home/.pi/agent"
rm -rf "$tmp_home/.pi/agent"
mkdir -p "$tmp_home/.pi"
cp -R "$persistent_home/.pi/agent" "$tmp_home/.pi/agent"
```

Aviso curto: `-v` do Docker pode criar pastas ausentes no host. Crie e confira
as pastas você mesmo quando o caminho importar.

Outro aviso: `.pi/agent` pode conter credenciais reais de provider, tokens
OAuth, settings, sessões, clones de pacotes, pacotes npm instalados, extensões,
skills, prompt templates, temas, logs, cache e outros estados privados. Copie
isso apenas para runs onde você aceita expor esse estado.

## Portas de preview

O serviço regular `agent` não publica portas fixas no host por padrão. Se o Pi
subir um app dentro de um run, publique só a porta necessária naquele comando:

```bash
docker compose run --rm -p 127.0.0.1:3001:3000 agent
```

Isso mapeia a porta `3001` do host para a porta `3000` do contêiner naquela
sessão. Faça o app dentro do contêiner escutar em `0.0.0.0`. Em uma VPS, use
`0.0.0.0:PORTA_HOST:PORTA_CONTAINER` apenas quando você realmente quiser expor o
app.

## Ollama / modelos locais

Pi suporta providers customizados por meio de:

```txt
${AGENT_HOME_PATH}/.pi/agent/models.json
```

Exemplo mínimo para um servidor Ollama no host Docker:

```json
{
  "providers": {
    "ollama": {
      "baseUrl": "http://host.docker.internal:11434/v1",
      "api": "openai-completions",
      "apiKey": "ollama",
      "models": [
        { "id": "example-model:8b" },
        { "id": "example-coder-model:7b" }
      ]
    }
  }
}
```

O campo `apiKey` é exigido pelo formato de configuração de modelos do Pi, mas o
Ollama ignora o valor.

Se o Ollama estiver em outra máquina da sua LAN, use esse IP no lugar:

```json
"baseUrl": "http://203.0.113.10:11434/v1"
```

Depois, abra o Pi e selecione o modelo com `/model`, ou inicie direto:

```bash
docker compose run --rm agent --provider ollama --model example-coder-model:7b
```

## Receitas

A partir da raiz do repositório, com `just`:

```bash
just setup pi
just config pi
just build pi
just rebuild pi
just run pi
just shell pi
just down pi
echo "Summarize the mounted project." | just run pi -p
```

A partir desta pasta do template, sem `just`:

```bash
./setup-host.sh
docker compose config --no-env-resolution
docker compose build
docker compose build --no-cache
docker compose run --rm agent
docker compose run --rm --entrypoint bash agent
docker compose down -v
echo "Summarize the mounted project." | docker compose run --rm -T agent -p
```

## O que vem dentro

- Base `debian trixie-slim` fixada por digest.
- Node.js 22 LTS + Pi Coding Agent (`@earendil-works/pi-coding-agent`).
- Python 3 + pip + venv.
- `build-essential` para projetos com dependências nativas.
- Utilitários de CLI: `git`, `rg`, `fd`, `jq`, `fzf`, `bat`, `tree`, `less`.
- Usuário não-root `agent`, com UID/GID alinhados ao host via build args.

## O que é montado

- `${WORKSPACE_PATH}` (host) -> `/workspace` (contêiner): seu projeto.
- `${AGENT_HOME_PATH}` (host) -> `/home/agent/` (contêiner): auth, config,
  sessões, pacotes e outros estados do Pi.

O contêiner em si é efêmero (`--rm`). Você pode destruir e recriar sem perder o
estado, porque os dois bind mounts continuam existindo no host.

Os dois caminhos são obrigatórios e devem ficar fora do checkout do `sannux`.
Isso evita repositórios Git aninhados e mantém as credenciais do agente fora
deste repositório. Como os bind mounts não criam caminhos no host
automaticamente, diretórios ausentes falham cedo em vez de aparecerem no lugar
errado.

## O Que Não Montar

Não monte seu home real do host, chaves SSH, credenciais de cloud, tokens de
gerenciadores de pacote, git config global, perfis de navegador ou homes de
outros agentes dentro deste contêiner.

Use um workspace dedicado e um `AGENT_HOME_PATH` dedicado por identidade do Pi.
Para runs one-shot efêmeros, copie apenas os arquivos de `.pi/agent` de que o
comando realmente precisa, lembrando que estado copiado do Pi pode incluir auth
real e histórico de sessão.

## Notas de segurança

A documentação do Pi é direta: não há popups de permissão por padrão. Ele espera
que você use um contêiner, construa seu próprio fluxo de confirmação ou adicione
extensões se precisar de controles mais rígidos.

Este template dá ao Pi uma casa pequena:

- ele vê `/workspace`;
- ele vê seu próprio `/home/agent`;
- ele pode usar a rede;
- ele não vê seu verdadeiro home do host, a menos que você o monte.

Isso ainda não é uma fronteira de segurança completa contra exfiltração de rede
do workspace. É um redutor prático do raio de impacto.

## Limites de recurso

O arquivo `.env` expõe:

```env
MEM_LIMIT=4g
CPU_LIMIT=4
```

Isso não é configuração de segurança. É só um freio para comandos que saem do
controle, builds pesados ou loops acidentais. `MEM_LIMIT` limita a memória do
contêiner, `CPU_LIMIT` limita a cota de CPU, e `pids_limit: 512` em
`compose.yml` limita a quantidade de processos/threads. Ajuste os valores ao
tamanho da sua VPS.

## Personalização

Edite `Dockerfile` e `compose.yml` diretamente. Adicione ferramentas que você
usa, ajuste configurações do Pi ou aperte mais o Compose para o seu ambiente.
Depois de mudar o `Dockerfile`, rode `just rebuild pi` a partir da raiz do
repositório, ou `docker compose build --no-cache` a partir desta pasta do
template.
