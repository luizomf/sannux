# codex

OpenAI Codex CLI running in Docker.

This template is intentionally small: configure one persistent agent home, test
it once in the TUI, then change only the Codex arguments for each run.

## What this template gives you

- `Dockerfile`: Codex CLI plus common Linux development tools.
- `compose.yml`: mounts your project at `/workspace` and the agent home at
  `/home/agent`.
- `setup-host.sh`: creates the host folders and writes safe `.env` defaults.

## Setup

Copy the environment file:

```bash
install -m 0600 .env.example .env
```

Ideally, edit these values so the workspace and agent home are explicit:

```env
WORKSPACE_PATH=/srv/example-data/workspaces/my-project
AGENT_HOME_PATH=/srv/example-data/agent-homes/codex
```

If you use an OpenAI API key instead of OAuth login, also set:

```env
OPENAI_API_KEY=sk-...
```

Keep `.env` private. It is loaded only by this template's Compose service, but
the key is still a real credential.

If `WORKSPACE_PATH` and `AGENT_HOME_PATH` stay empty, `setup-host.sh` uses this
fallback:

```txt
~/sannux-data/workspaces/codex
~/sannux-data/agent-homes/codex
```

Create the host folders and fill missing `.env` values:

```bash
./setup-host.sh
```

Test the TUI once:

```bash
docker compose run --rm agent
```

From the repo root, the same flow is:

```bash
just setup codex
just run codex
```

Choose one auth path:

- API key: set `OPENAI_API_KEY` in `.env`, then run the TUI or one-shot commands
  normally. No Codex login is needed. If you do not set it ahead of time, the
  Codex prompt can also ask you to provide an API key inside the container.
- OAuth/subscription login: leave `OPENAI_API_KEY` unset and let Codex prompt for
  login on the first TUI run. Inside Docker, choose **Sign in with Device Code**.
  Do not choose **Sign in with ChatGPT** in the container: that path assumes a
  local desktop browser and does not fit this Docker image.
- Headless OAuth/subscription login: run this once on a machine without a
  browser:

```bash
docker compose run --rm agent login --device-auth
```

OAuth tokens land in `${AGENT_HOME_PATH}/.codex/auth.json` on your host, so later
`docker compose run --rm agent` calls skip authentication.

## Scenarios

### 1. Template

The template is the harness-specific environment: `codex` means OpenAI Codex CLI
with its normal OpenAI auth and config flow.

Other templates follow the same idea for other harnesses or providers, such as
`codex-ollama`, `claude-ollama`, Gemini, Pi, or opencode.

### 2. Initial persistent config

`.env` plus `setup-host.sh` creates the first working agent home.

For this harness, provider auth is either `OPENAI_API_KEY` from `.env` or OAuth
login state under `.codex`. API key users can run without any pre-seeded
`.codex` auth. OAuth users should keep the persistent agent home for login state.

The agent home can also store config, sessions, logs, cache, memory, shell
history, MCP config, plugins, and other runtime state under `/home/agent`.

### 3. Persistent TUI run

Use this for normal interactive work:

```bash
docker compose run --rm agent
```

From the repo root:

```bash
just run codex
```

This shares the persistent workspace and persistent agent home from `.env`.

For an interactive shell instead of the agent:

```bash
docker compose run --rm --entrypoint bash agent
```

### 4. Persistent daemon run

This template does not provide a Codex daemon service.

Codex CLI is run as an interactive TUI or as a one-shot `codex exec` command. If
a future Codex CLI release adds a stable daemon/server mode, add it as an
explicit Compose profile and document its ports, auth, logs, and shutdown flow
here.

### 5. One-shot run with persistent home

Use this when sharing the same agent home is acceptable:

```bash
printf '%s\n' "Summarize this project." | \
  docker compose run --rm -T agent exec \
    --ephemeral --dangerously-bypass-approvals-and-sandbox -
```

This is simple, but the run can read and write the full persistent
`AGENT_HOME_PATH`: config, auth, cache, logs, history, memory, MCP config,
plugins, and runtime state. `--ephemeral` tells Codex not to persist that exec
session.

You can also override the workspace for one command:

```bash
tmp_workspace=/srv/example-data/tmp/workspace-1
mkdir -p "$tmp_workspace"

printf '%s\n' "Summarize this temporary workspace." | \
  docker compose run \
    -v "$tmp_workspace:/workspace" \
    --rm -T agent exec \
    --ephemeral --dangerously-bypass-approvals-and-sandbox -
```

This still uses the persistent agent home from `.env`; only `/workspace` is
overridden for that command.

### 6. One-shot run with ephemeral home

For Codex, a useful ephemeral home still needs the tested `.codex` directory.
That directory carries login/auth, config, and any Codex state you accept
exposing to this run. The rest of `/home/agent` stays temporary.

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

Short warning: Docker `-v` can create missing host folders. Create and inspect
the folders yourself when the path matters.

This exposes everything inside `.codex`. It may include API keys, auth state,
config, memories, or other Codex data. The point is not "no sensitive data"; it
is "only the minimum you accept exposing for this run."

If you use only `OPENAI_API_KEY` from `.env` and do not need any Codex config,
you can omit the `.codex` mount. Most users should keep it because OAuth login
and CLI config live there.

## Preview ports

If the agent starts an app inside the container, publish only the port needed for
that run:

```bash
docker compose run --rm -p 127.0.0.1:3001:3000 agent
```

Make the app listen on `0.0.0.0` inside the container. On a VPS, expose
`0.0.0.0:HOST_PORT:CONTAINER_PORT` only when you really want public access.

## Permission model

One-shot examples use:

```bash
--dangerously-bypass-approvals-and-sandbox
```

That is intentional here: Docker is the sandbox boundary for those commands. The
agent can see the mounted workspace, mounted agent home, and network.

For interactive TUI work, choose the permission mode you want inside Codex.

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

## What's inside

- Debian trixie-slim base pinned by digest.
- Node.js 22 LTS + Codex CLI (`@openai/codex`).
- Python 3 + pip + venv.
- `build-essential` for projects with native deps.
- CLI helpers: `git`, `rg`, `fd`, `jq`, `fzf`, `bat`, `tree`, `less`.
- Non-root user `agent`, UID/GID matched to your host via build args.

## What's mounted

- `${WORKSPACE_PATH}` (host) -> `/workspace` (container): your project.
- `${AGENT_HOME_PATH}` (host) -> `/home/agent` (container): Codex state.

Both paths should live outside the `sannux` checkout. The Compose bind mounts use
`create_host_path: false`, so missing directories fail early instead of being
created in the wrong place.

## Resource limits

`MEM_LIMIT`, `CPU_LIMIT`, and `pids_limit` are resource caps, not security. Tune
them to your VPS or Docker Desktop allocation.

## Customize

Edit `Dockerfile` and `compose.yml` directly. Add tools you reach for, adjust
Codex config in the agent home, or tighten Compose settings for your deployment.
After changing the image:

```bash
docker compose build --no-cache
```
