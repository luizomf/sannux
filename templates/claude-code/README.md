# claude-code

Claude Code running in Docker with Anthropic auth. It supports normal
interactive TUI runs, one-shot runs, and an optional Remote Control daemon.

This template is intentionally simple: configure one persistent workspace and
one persistent agent home, test the TUI once, then choose whether each run is
interactive, daemonized, persistent one-shot, or ephemeral one-shot.

## What this template gives you

- `Dockerfile`: Claude Code plus common Linux development tools.
- `compose.yml`: mounts your project at `/workspace` and the agent home at
  `/home/agent`.
- `setup-host.sh`: creates the host folders, writes safe `.env` defaults, and
  prepares Claude state files.
- `remote-control`: an optional daemon service for Claude Code Remote Control.

## Setup

Copy the environment file:

```bash
install -m 0600 .env.example .env
```

Ideally, edit these values so the workspace and agent home are explicit:

```env
WORKSPACE_PATH=/path/to/workspaces/my-project
AGENT_HOME_PATH=/path/to/agent-homes/claude-code
```

If `WORKSPACE_PATH` and `AGENT_HOME_PATH` stay empty, `setup-host.sh` uses this
fallback:

```txt
~/sannux-data/workspaces/claude-code
~/sannux-data/agent-homes/claude-code
```

Create the host folders and fill missing `.env` values:

```bash
./setup-host.sh
```

Start and test the TUI once:

```bash
docker compose run --rm agent
```

From the repo root, the same flow is:

```bash
just setup claude-code
just run claude-code
```

## Scenarios

### 1. Template

The template is the harness-specific environment: `claude-code` means Claude
Code configured for real Anthropic/Claude Code usage.

Other templates follow the same idea for other harnesses, such as Codex,
Claude with Ollama, Gemini, Pi, or opencode.

### 2. Initial persistent config

`.env` plus `setup-host.sh` creates the first working agent home.

For normal Claude Code runs, authenticate either with `ANTHROPIC_API_KEY` in
`.env` or with Claude Code's login flow inside the container. The login/config
state lives in the persisted `AGENT_HOME_PATH`, not in your real host home.

Claude Code stores important user-level state under `/home/agent/.claude/` and
`/home/agent/.claude.json`: auth, settings, trusted projects, sessions, MCP
config, hooks, cache, and other runtime state. Treat both paths as private.

Remote Control is a real Claude Code daemon flow. Use real Claude Code
Anthropic auth in the persisted home for it; an Ollama-style placeholder `.env`
is not enough.

### 3. Persistent TUI run

Use this for normal interactive work:

```bash
docker compose run --rm agent
```

From the repo root:

```bash
just run claude-code
```

This run stays active until you leave the TUI. It uses the persistent workspace
and persistent agent home from `.env`.

### 4. Persistent daemon run

Use this when you want Claude Code Remote Control to stay running in the
background:

```bash
docker compose --profile daemon up -d remote-control
docker compose logs -f remote-control
docker compose stop remote-control
```

From the repo root:

```bash
just up claude-code remote-control
just logs claude-code remote-control
just ps claude-code
just down claude-code
```

The daemon runs:

```bash
claude -n main-session --remote-control
```

It uses the same persistent `WORKSPACE_PATH` and `AGENT_HOME_PATH` as the TUI.
Change the workspace by changing `WORKSPACE_PATH` in `.env` before starting the
daemon, or by overriding that Compose variable for that start. Keep the agent
home the same unless you intentionally want a different Claude identity.

Treat the Remote Control URL as a secret. Anyone with access to that session can
drive Claude Code inside the mounted workspace.

### 5. One-shot run with persistent home

Use this when sharing the same agent home is acceptable:

```bash
printf '%s\n' "Summarize this project." | \
  docker compose run --rm -T agent \
    --dangerously-skip-permissions --no-session-persistence -p -
```

This is simple, but the run can read and write the full persistent
`AGENT_HOME_PATH`: auth, settings, sessions, cache, logs, history, plugins, MCP
config, hooks, trusted projects, and runtime state. `--no-session-persistence`
tells Claude Code not to save that conversation.

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
Claude state files from the persistent home:

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

printf '%s\n' "Summarize this temporary workspace." | \
  docker compose --project-directory "$template_dir" run \
    -v "$tmp_workspace:/workspace" \
    -v "$tmp_home:/home/agent" \
    --rm -T agent \
    --dangerously-skip-permissions --no-session-persistence -p -
```

Short warning: Docker `-v` can create missing host folders. Create and inspect
the folders yourself when the path matters.

For Claude Code, the copied `.claude` directory and `.claude.json` file may
contain real auth, settings, trusted projects, MCP config, hooks, and cached
state. Copy them only into runs where you accept exposing that state.

## Preview ports

The regular `agent` service does not publish fixed host ports by default. If
Claude Code starts an app inside a run, publish only the port you need on that
command:

```bash
docker compose run --rm -p 127.0.0.1:3001:3000 agent
```

That maps host port `3001` to container port `3000` for that one session. Make
the app inside the container listen on `0.0.0.0`.

The `remote-control` daemon publishes the configured `HOST_PORT_*` values
because it is a persistent remote endpoint. On a VPS, set
`PORT_BIND_ADDRESS=0.0.0.0` only when you intentionally want to expose those
ports.

## Permission model

The TUI and daemon use Claude Code's normal permission behavior. One-shot
examples use:

```bash
--dangerously-skip-permissions
```

That is a command-level choice for unattended runs where Docker is the sandbox
boundary. The agent can see the mounted workspace, mounted agent home, and
network.

## What not to mount

Do not casually mount:

- your real home directory;
- SSH keys;
- cloud credentials;
- package manager tokens;
- global Git or GitHub config;
- the Docker socket.

Mount the project folder Claude Code should edit, and mount only the Claude
state you are willing to expose to that run.

## What's inside

- Debian trixie-slim base pinned by digest.
- Node.js 22 LTS + Claude Code (`@anthropic-ai/claude-code`).
- Python 3 + pip + venv.
- `build-essential` for projects with native deps.
- CLI helpers: `git`, `rg`, `fd`, `jq`, `fzf`, `bat`, `tree`, `less`, `tmux`.
- Non-root user `agent`, UID/GID matched to your host via build args.

## What's mounted

- `${WORKSPACE_PATH}` (host) -> `/workspace` (container): your project.
- `${AGENT_HOME_PATH}` (host) -> `/home/agent` (container): Claude state.

Both paths should live outside the `sannux` checkout. The Compose bind mounts use
`create_host_path: false`, so missing directories fail early instead of being
created in the wrong place.

## Resource limits

`MEM_LIMIT`, `CPU_LIMIT`, and `pids_limit` are resource caps, not security. Tune
them to your VPS or Docker Desktop allocation.

## Customize

Edit `Dockerfile` and `compose.yml` directly. Add tools you reach for, flip on
stricter security flags (`read_only: true`, `cap_drop: [ALL]`, custom
`seccomp`), or swap the base image. After changing `Dockerfile`, run
`just rebuild claude-code` from the repo root, or `docker compose build
--no-cache` from this template folder.
