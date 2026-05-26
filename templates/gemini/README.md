# gemini

[Google Gemini CLI](https://github.com/google-gemini/gemini-cli) running in a
Debian-slim Docker container.

This template is intentionally simple: configure one persistent workspace and
one persistent agent home, authenticate Gemini once, then choose whether each
run is interactive, persistent one-shot, or ephemeral one-shot.

## Example Vídeo (PT-BR 🇧🇷)

Example using `codex-ollama` (in Brazilian Portuguese).

[![Agentes de IA Seguros no Docker](https://i3.ytimg.com/vi/wqe0VU5L5aU/maxresdefault.jpg)](https://youtu.be/wqe0VU5L5aU)

- [youtu.be/wqe0VU5L5aU](https://youtu.be/wqe0VU5L5aU)

## What this template gives you

- `Dockerfile`: Gemini CLI plus common Linux development tools.
- `compose.yml`: mounts your project at `/workspace` and the agent home at
  `/home/agent`.
- `setup-host.sh`: creates the host folders, writes safe `.env` defaults, and
  prepares `${AGENT_HOME_PATH}/.gemini`.

Gemini CLI itself is installed from the npm package `@google/gemini-cli`.

## Setup

Copy the environment file:

```bash
install -m 0600 .env.example .env
```

Ideally, edit these values so the workspace and agent home are explicit:

```env
WORKSPACE_PATH=/path/to/workspaces/my-project
AGENT_HOME_PATH=/path/to/agent-homes/gemini
```

If `WORKSPACE_PATH` and `AGENT_HOME_PATH` stay empty, `setup-host.sh` uses this
fallback:

```txt
~/sannux-data/workspaces/gemini
~/sannux-data/agent-homes/gemini
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
just setup gemini
just run gemini
```

## Scenarios

### 1. Template

The template is the harness-specific environment: `gemini` means Google Gemini
CLI running with its own workspace and isolated agent home.

Other templates follow the same idea for other harnesses, such as Codex, Claude,
Hermes, Pi, or opencode.

### 2. Initial persistent config

`.env` plus `setup-host.sh` creates the first working agent home.

Authenticate Gemini with one of these options:

- `GEMINI_API_KEY` in `.env`;
- Google OAuth in the Gemini TUI;
- Vertex AI values such as `GOOGLE_API_KEY`, `GOOGLE_GENAI_USE_VERTEXAI=true`,
  and `GOOGLE_CLOUD_PROJECT`.

Gemini stores user-level state under `/home/agent/.gemini/`. That can include
OAuth credentials, settings, trusted folders, the project registry, sessions,
history, MCP OAuth tokens, policies, extensions, skills, cache, and other
runtime state. Treat it as private.

### 3. Persistent TUI run

Use this for normal interactive work:

```bash
docker compose run --rm agent
```

From the repo root:

```bash
just run gemini
```

This run stays active until you leave the TUI. It uses the persistent workspace
and persistent agent home from `.env`.

### 4. Persistent daemon run

This template does not provide a Gemini daemon service.

Gemini CLI is run as an interactive TUI or as a one-shot command. If a future
Gemini CLI release adds a stable daemon/server mode, add it as an explicit
Compose profile service and document its ports, logs, and shutdown flow here.

### 5. One-shot run with persistent home

Use this when sharing the same agent home is acceptable:

```bash
docker compose run --rm agent -p "summarize the mounted project"
```

From the repo root:

```bash
just run gemini -p "summarize the mounted project"
```

Gemini CLI reports `-p` / `--prompt` as non-interactive headless mode.

Important: stdin is appended to the `-p` prompt. Use one prompt source for
normal automation. Combine stdin and `-p` only when you intentionally want both
pieces of text in the same request.

For example, this read-only prompt uses plan mode:

```bash
docker compose run --rm -T agent \
  --approval-mode plan \
  -p "Summarize the mounted project."
```

For write tasks, make the approval mode explicit. In non-interactive one-shot
runs, do not ask Gemini to edit files without `--yolo` or
`--approval-mode yolo`; it can spend a long time trying the edit and then report
that it had no approval to continue.

```bash
docker compose run --rm -T agent \
  --yolo \
  -p "Create /workspace/iso_date.txt with the current date in ISO 8601 format."
```

And this intentionally sends extra context through stdin:

```bash
printf '%s\n' "You are running inside a Docker container." | \
  docker compose run --rm -T agent \
    --yolo \
    -p "Report the OS and create /workspace/iso_date.txt with the current date."
```

This is simple, but the run can read and write the full persistent
`AGENT_HOME_PATH`: auth, settings, trusted folders, sessions, cache, logs,
history, MCP config, policies, extensions, skills, and runtime state.

Use `--approval-mode plan` for read-only one-shot checks:

```bash
docker compose run --rm -T agent \
  --approval-mode plan \
  -p "summarize the mounted project"
```

Use `--approval-mode yolo` or `--yolo` only for runs where you accept automatic
edits and shell commands inside the mounted workspace.

### 6. One-shot run with ephemeral home

Use this when you want a fresh `/home/agent` for one command.

With an API key in `.env`, an empty temporary home is enough:

```bash
template_dir=/path/to/sannux/templates/gemini
tmp_workspace=/path/to/tmp/workspace-1
tmp_home="$(mktemp -d)"
trap 'rm -rf "$tmp_home"' EXIT

mkdir -p "$tmp_workspace"

docker compose --project-directory "$template_dir" run \
  -v "$tmp_workspace:/workspace" \
  -v "$tmp_home:/home/agent" \
  --rm -T agent \
  --yolo \
  -p "Create /workspace/test.txt with the current date in ISO 8601 format."
```

If you rely on OAuth login, MCP servers, extensions, skills, or other Gemini
state from the persistent home, copy only the state you accept exposing to the
run:

```bash
persistent_home=/path/to/agent-homes/gemini
test -d "$persistent_home/.gemini"
cp -R "$persistent_home/.gemini" "$tmp_home/.gemini"
```

Short warning: Docker `-v` can create missing host folders. Create and inspect
the folders yourself when the path matters.

Another warning: `.gemini` may contain real auth, trusted folders, MCP OAuth
tokens, settings, project registry, history, policies, extensions, skills,
cache, or other private state. Copy it only into runs where you accept exposing
that state.

## Preview ports

The regular `agent` service does not publish fixed host ports by default. If
Gemini starts an app inside a run, publish only the port you need on that
command:

```bash
docker compose run --rm -p 127.0.0.1:3001:3000 agent
```

That maps host port `3001` to container port `3000` for that one session. Make
the app inside the container listen on `0.0.0.0`. On a VPS, expose
`0.0.0.0:HOST_PORT:CONTAINER_PORT` only when you really want public access.

## What's inside

- Debian trixie-slim base pinned by digest.
- Node.js 22 LTS + Gemini CLI (`@google/gemini-cli`).
- Python 3 + pip + venv, so the agent can spin up Python tasks.
- `build-essential` for projects with native deps.
- CLI helpers: `git`, `rg`, `fd`, `jq`, `fzf`, `bat`, `tree`, `less`.
- Non-root user `agent`, UID/GID matched to your host via build args.

## What not to mount

Do not casually mount:

- your real home directory;
- SSH keys;
- cloud credentials;
- package manager tokens;
- global Git or GitHub config;
- the Docker socket.

Mount the project folder Gemini should edit, and mount only the Gemini data you
are willing to expose to that run.

## Customize

Edit `Dockerfile` and `compose.yml` directly. Add tools you reach for, flip on
stricter security flags (`read_only: true`, `cap_drop: [ALL]`, custom
`seccomp`), or swap the base image. After changing `Dockerfile`, run:

```bash
docker compose build --no-cache
```
