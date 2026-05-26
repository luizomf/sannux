# claude-ollama

Claude Code running in Docker, pointed at an Ollama server through an
Anthropic-compatible endpoint.

This template is intentionally small: configure one persistent agent home, test
it once in the TUI, then change only the Claude arguments for each run.

## Example Vídeo (PT-BR 🇧🇷)

Example using `codex-ollama` (in Brazilian Portuguese).

[![Agentes de IA Seguros no Docker](https://i3.ytimg.com/vi/wqe0VU5L5aU/maxresdefault.jpg)](https://youtu.be/wqe0VU5L5aU)

- [youtu.be/wqe0VU5L5aU](https://youtu.be/wqe0VU5L5aU)

## What this template gives you

- `Dockerfile`: Claude Code plus common Linux development tools.
- `compose.yml`: mounts your project at `/workspace` and the agent home at
  `/home/agent`.
- `setup-host.sh`: creates the host folders and writes safe `.env` defaults.

Ollama itself runs outside this container.

## Setup

Copy the environment file:

```bash
install -m 0600 .env.example .env
```

Ideally, edit these values so the workspace and agent home are explicit:

```env
WORKSPACE_PATH=/path/to/workspaces/my-project
AGENT_HOME_PATH=/path/to/agent-homes/claude-ollama
ANTHROPIC_BASE_URL=http://host.docker.internal:11434
ANTHROPIC_MODEL=example-ollama-model
```

If `WORKSPACE_PATH` and `AGENT_HOME_PATH` stay empty, `setup-host.sh` uses this
fallback:

```txt
~/sannux-data/workspaces/claude-ollama
~/sannux-data/agent-homes/claude-ollama
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
just setup claude-ollama
just run claude-ollama
```

## Scenarios

### 1. Template

The template is the harness-specific environment: `claude-ollama` means Claude
Code configured to use an Ollama endpoint.

Other templates follow the same idea for other harnesses, such as Codex, Claude,
Gemini, Pi, or opencode.

### 2. Initial persistent config

`.env` plus `setup-host.sh` creates the first working agent home.

For this harness, Ollama routing is just environment variables:
`ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_API_KEY`, and
`ANTHROPIC_MODEL`.

The agent home still matters. Claude Code can store settings, sessions, logs,
cache, shell history, plugins, MCP config, and other runtime state under
`/home/agent`.

### 3. Persistent TUI run

Use this for normal interactive work:

```bash
docker compose run --rm agent
```

From the repo root:

```bash
just run claude-ollama
```

This shares the persistent workspace and persistent agent home from `.env`.

### 4. Persistent daemon run

This template does not provide a Claude/Ollama daemon service.

Claude Code is run as an interactive TUI or as a one-shot command against the
configured Ollama-compatible endpoint. If a daemon profile is added later,
document its ports, auth, logs, and shutdown flow here.

### 5. One-shot run with persistent home

Use this when sharing the same agent home is acceptable:

```bash
printf '%s\n' "Summarize this project." | \
  docker compose run --rm -T agent \
    --dangerously-skip-permissions --no-session-persistence -p -
```

This is simple, but the run can read and write the full persistent
`AGENT_HOME_PATH`: settings, sessions, cache, logs, history, plugins, MCP
config, and runtime state. `--no-session-persistence` tells Claude Code not to
save that conversation.

You can also override the workspace for one command:

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

This still uses the persistent agent home from `.env`; only `/workspace` is
overridden for that command.

### 6. One-shot run with ephemeral home

Use this when you want a fresh `/home/agent` for one command while reusing the
Claude state files that `setup-host.sh` prepared in the persistent home:

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

printf '%s\n' "Summarize this temporary workspace." | \
  docker compose --project-directory "$template_dir" run \
    -v "$tmp_workspace:/workspace" \
    -v "$tmp_home:/home/agent" \
    --rm -T agent \
    --dangerously-skip-permissions --no-session-persistence -p -
```

Short warning: Docker `-v` can create missing host folders. Create and inspect
the folders yourself when the path matters.

For Ollama, `setup-host.sh` creates a minimal `.claude.json` with
`firstStartTime`. Claude Code still expects that file shape. The example copies
Claude state into the temporary home instead of bind-mounting nested files,
because Docker can create missing file sources as directories and nested file
mounts under `/home/agent` are fragile. If your persistent home later contains
real Claude auth or custom state, inspect `.claude` and `.claude.json` before
copying them into an ephemeral run.

## Preview ports

If the agent starts an app inside the container, publish only the port needed
for that run:

```bash
docker compose run --rm -p 127.0.0.1:3001:3000 agent
```

Make the app listen on `0.0.0.0` inside the container. On a VPS, expose
`0.0.0.0:HOST_PORT:CONTAINER_PORT` only when you really want public access.

## Reasoning / thinking

Claude Code exposes an `--effort` flag:

```bash
docker compose run --rm agent --effort high
```

This flag belongs to the Claude Code harness. Valid values are `low`, `medium`,
`high`, `xhigh`, and `max`. Values such as `false` are rejected before the
request reaches Ollama.

With Ollama, whether effort changes anything depends on the Anthropic-compatible
endpoint and the model. If your model has native thinking controls, treat those
as an Ollama model/provider detail rather than something this Docker template
can guarantee.

## Permission model

This template runs Claude Code with:

```bash
--dangerously-skip-permissions
```

That is intentional here: Docker is the sandbox boundary. The agent can see the
mounted workspace, mounted agent home, and network.

## What not to mount

Do not casually mount:

- your real home directory;
- SSH keys;
- cloud credentials;
- package manager tokens;
- global Git or GitHub config;
- the Docker socket.

Mount the project folder the agent should edit, and mount only the agent data
you are willing to expose to that run.

## What's inside

- Debian trixie-slim base pinned by digest.
- Node.js 22 LTS + Claude Code (`@anthropic-ai/claude-code`).
- Python 3 + pip + venv.
- `build-essential` for projects with native deps.
- CLI helpers: `git`, `rg`, `fd`, `jq`, `fzf`, `bat`, `tree`, `less`.
- Non-root user `agent`, UID/GID matched to your host via build args.

## What's mounted

- `${WORKSPACE_PATH}` (host) -> `/workspace` (container): your project.
- `${AGENT_HOME_PATH}` (host) -> `/home/agent` (container): Claude state.

Both paths should live outside the `sannux` checkout. The Compose bind mounts
use `create_host_path: false`, so missing directories fail early instead of
being created in the wrong place.

## Resource limits

`MEM_LIMIT`, `CPU_LIMIT`, and `pids_limit` are resource caps, not security. Tune
them to your VPS or Docker Desktop allocation.

## Customize

Edit `Dockerfile` and `compose.yml` directly. Add tools you reach for, adjust
Ollama routing, or tighten Compose settings for your deployment. After changing
the image:

```bash
docker compose build --no-cache
```
