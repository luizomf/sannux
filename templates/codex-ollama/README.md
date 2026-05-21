# codex-ollama

Codex CLI running in Docker, pointed at an Ollama server through its
OpenAI-compatible `/v1` endpoint.

This template is intentionally small: configure one persistent agent home, test
it once in the TUI, then change only the Codex arguments for each run.

## What this template gives you

- `Dockerfile`: Codex CLI plus common Linux development tools.
- `compose.yml`: mounts your project at `/workspace` and the agent home at
  `/home/agent`.
- `setup-host.sh`: creates the host folders and writes
  `${AGENT_HOME_PATH}/.codex/config.toml`.
- `model_catalog.json`: Codex metadata for the local Ollama model.

Ollama itself runs outside this container.

## Setup

Copy the environment file:

```bash
install -m 0600 .env.example .env
```

Ideally, edit these values so the workspace and agent home are explicit:

```env
WORKSPACE_PATH=/srv/example-data/workspaces/my-project
AGENT_HOME_PATH=/srv/example-data/agent-homes/codex-ollama
OLLAMA_BASE_URL=http://host.docker.internal:11434/v1
CODEX_MODEL=local-model:8b
```

If `WORKSPACE_PATH` and `AGENT_HOME_PATH` stay empty, `setup-host.sh` uses this
fallback:

```txt
~/sannux-data/workspaces/codex-ollama
~/sannux-data/agent-homes/codex-ollama
```

Render the Codex config and create the host folders:

```bash
./setup-host.sh
```

Test the TUI once:

```bash
docker compose run --rm agent
```

From the repo root, the same flow is:

```bash
just setup codex-ollama
just run codex-ollama
```

## Scenarios

### 1. Template

The template is the harness-specific environment: `codex-ollama` means Codex CLI
configured to use an Ollama endpoint.

Other templates follow the same idea for other harnesses, such as Codex, Claude,
Gemini, Pi, or opencode.

### 2. Initial persistent config

`.env` plus `setup-host.sh` creates the first working agent home.

That home stores the Codex config, login/API state, model, endpoint, effort,
history, cache, logs, and anything else the CLI writes under `/home/agent`.

### 3. Persistent TUI run

Use this for normal interactive work:

```bash
docker compose run --rm agent
```

From the repo root:

```bash
just run codex-ollama
```

This shares the persistent workspace and persistent agent home from `.env`.

### 4. Persistent daemon run

This template does not provide a Codex/Ollama daemon service.

Codex CLI is run as an interactive TUI or as a one-shot `codex exec` command. If
a future Codex CLI release adds a stable daemon/server mode, add it as an
explicit Compose profile and document its ports, auth, logs, and shutdown flow
here.

### 5. One-shot run with persistent home

Use this when sharing the same agent home is acceptable:

```bash
printf '%s\n' "Summarize this project." | \
  docker compose run --rm -T agent exec - --ephemeral --yolo
```

This is simple, but the run can read and write the full persistent
`AGENT_HOME_PATH`: config, auth, cache, logs, history, memory, and runtime state.

### 6. One-shot run with ephemeral home

Use this when you want a fresh `/home/agent` for one command, while reusing only
the tested Codex config directory:

```bash
persistent_home=/srv/example-data/agent-homes/codex-ollama
tmp_workspace=/srv/example-data/tmp/workspace-1
tmp_home=/srv/example-data/tmp/home-1

mkdir -p "$tmp_workspace" "$tmp_home"
test -d "$persistent_home/.codex"

printf '%s\n' "Summarize this temporary workspace." | \
  docker compose run \
    -v "$tmp_workspace:/workspace" \
    -v "$tmp_home:/home/agent" \
    -v "$persistent_home/.codex:/home/agent/.codex" \
    --rm -T agent exec - --ephemeral --yolo
```

Short warning: Docker `-v` can create missing host folders. Create and inspect
the folders yourself when the path matters.

Another warning: this exposes everything inside `.codex`. That may include API
keys, auth state, config, memories, or other Codex data. The point is not "no
sensitive data"; it is "only the minimum you accept exposing for this run."

## Preview ports

If the agent starts an app inside the container, publish only the port needed for
that run:

```bash
docker compose run --rm -p 127.0.0.1:3001:3000 agent
```

Make the app listen on `0.0.0.0` inside the container. On a VPS, expose
`0.0.0.0:HOST_PORT:CONTAINER_PORT` only when you really want public access.

## Model catalog

Codex needs model metadata for local Ollama model names. This template mounts:

```txt
./model_catalog.json -> /opt/sannux/model_catalog.json
```

If you change `CODEX_MODEL`, keep `model_catalog.json` aligned.

## Permission model

The generated Codex config uses:

```toml
approval_policy = "never"
sandbox_mode = "danger-full-access"
```

That is intentional here: Docker is the sandbox boundary. The agent can see the
mounted workspace, mounted agent home, read-only model catalog, and network.

## What not to mount

Do not casually mount:

- your real home directory;
- SSH keys;
- cloud credentials;
- package manager tokens;
- global Git or GitHub config;
- the Docker socket.

Mount the project folder the agent should edit, and mount only the agent data you
are willing to expose to that run.

## Customize

Edit `Dockerfile`, `compose.yml`, `model_catalog.json`, or
`codex-config.toml.template` directly. After changing the image:

```bash
docker compose build --no-cache
```
