# opencode

[OpenCode](https://opencode.ai/docs/) running in a Debian-slim Docker container.

This template is intentionally simple: configure one persistent workspace and
one persistent agent home, authenticate OpenCode once, then choose whether each
run is interactive, persistent one-shot, or ephemeral one-shot.

Real credentialed OpenCode runs have not been tested yet; PRs with verified
provider-specific notes are welcome.

## Example Vídeo (PT-BR 🇧🇷)

Example using `codex-ollama` (in Brazilian Portuguese).

[![Agentes de IA Seguros no Docker](https://i3.ytimg.com/vi/wqe0VU5L5aU/maxresdefault.jpg)](https://youtu.be/wqe0VU5L5aU)

- [youtu.be/wqe0VU5L5aU](https://youtu.be/wqe0VU5L5aU)

## What this template gives you

- `Dockerfile`: OpenCode CLI plus common Linux development tools.
- `compose.yml`: Docker Compose service that mounts your project at `/workspace`
  and the agent home at `/home/agent`.
- `setup-host.sh`: creates the host folders, writes safe `.env` defaults, and
  prepares OpenCode config/data directories.

OpenCode itself is installed from the npm package `opencode-ai`.

## Setup

Copy the environment file:

```bash
install -m 0600 .env.example .env
```

Ideally, edit these values so the workspace and agent home are explicit:

```env
WORKSPACE_PATH=/path/to/workspaces/my-project
AGENT_HOME_PATH=/path/to/agent-homes/opencode
```

If `WORKSPACE_PATH` and `AGENT_HOME_PATH` stay empty, `setup-host.sh` uses this
fallback:

```txt
~/sannux-data/workspaces/opencode
~/sannux-data/agent-homes/opencode
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
just setup opencode
just run opencode
```

## Scenarios

### 1. Template

The template is the harness-specific environment: `opencode` means OpenCode CLI
running with its own workspace and isolated agent home.

Other templates follow the same idea for other harnesses, such as Codex, Claude,
Gemini, Hermes, or Pi.

### 2. Initial persistent config

`.env` plus `setup-host.sh` creates the first working agent home.

Authenticate OpenCode with one of these options:

- set provider keys such as `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`,
  `GEMINI_API_KEY`, `GROQ_API_KEY`, or `OPENROUTER_API_KEY` in `.env`;
- run `docker compose run --rm agent auth login` and pick a provider;
- run the OpenCode TUI and use `/connect`.

OpenCode docs state that `opencode auth login` stores credentials in
`~/.local/share/opencode/auth.json`. With this template, that is:

```txt
${AGENT_HOME_PATH}/.local/share/opencode/auth.json
```

Global OpenCode config lives under `~/.config/opencode/opencode.json`, with TUI
settings in `~/.config/opencode/tui.json`. Project config can also live in
`opencode.json` or `.opencode/` under `/workspace`.

Treat the whole agent home as private. It can contain provider credentials,
global config, project config copies, sessions, snapshots, history, cache, MCP
OAuth tokens, plugins, skills, logs, and other runtime state.

### 3. Persistent TUI run

Use this for normal interactive work:

```bash
docker compose run --rm agent
```

From the repo root:

```bash
just run opencode
```

This run stays active until you leave the TUI. It uses the persistent workspace
and persistent agent home from `.env`.

### 4. Persistent daemon run

This template does not provide an OpenCode daemon service yet.

OpenCode CLI docs include `opencode serve`, `opencode web`, and
`opencode attach`, but this template has not been validated with real
credentials as a long-running server profile. Until that is tested, prefer the
interactive TUI or one-shot runs below. If a daemon profile is added later,
document its ports, auth, logs, and shutdown flow here.

### 5. One-shot run with persistent home

Use this when sharing the same agent home is acceptable:

```bash
docker compose run --rm -T agent run "Summarize the mounted project."
```

From the repo root:

```bash
just run opencode run "Summarize the mounted project."
```

OpenCode docs describe `opencode run [message..]` as non-interactive mode for
scripting and automation.

By default, OpenCode permissions are permissive: most operations are allowed,
while `doom_loop` and `external_directory` ask. Configure `permission` in
`opencode.json` when you want reads, edits, shell commands, or external
directories to ask or deny. A read-only one-shot can use project config like:

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

For unattended write tasks, make the permission tradeoff explicit:

```bash
docker compose run --rm -T agent run \
  --dangerously-skip-permissions \
  "Create /workspace/test.txt with the current date in ISO 8601 format."
```

Local `opencode run --help` reports `--dangerously-skip-permissions` as:
auto-approve permissions that are not explicitly denied. Keep explicit `deny`
rules in config for anything the run must never do.

This is simple, but the run can read and write the full persistent
`AGENT_HOME_PATH`: auth, settings, sessions, snapshots, cache, logs, history,
MCP config, plugins, skills, and runtime state.

### 6. One-shot run with ephemeral home

Use this when you want a fresh `/home/agent` for one command.

With provider API keys in `.env`, an empty temporary home should be enough:

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

For read-only prompts, leave `--dangerously-skip-permissions` out and use an
OpenCode `permission` config that asks or denies writes and shell commands:

```bash
docker compose --project-directory "$template_dir" run \
  -v "$tmp_workspace:/workspace" \
  -v "$tmp_home:/home/agent" \
  --rm -T agent \
  run "Summarize the mounted project."
```

If you rely on `opencode auth login`, `/connect`, MCP OAuth, plugins, skills, or
global OpenCode config from the persistent home, copy only the state you accept
exposing to the run:

```bash
persistent_home=/path/to/agent-homes/opencode
test -d "$persistent_home/.config/opencode"
test -d "$persistent_home/.local/share/opencode"
rm -rf "$tmp_home/.config/opencode" "$tmp_home/.local/share/opencode"
mkdir -p "$tmp_home/.config" "$tmp_home/.local/share"
cp -R "$persistent_home/.config/opencode" "$tmp_home/.config/opencode"
cp -R "$persistent_home/.local/share/opencode" "$tmp_home/.local/share/opencode"
```

Short warning: Docker `-v` can create missing host folders. Create and inspect
the folders yourself when the path matters.

Another warning: `.config/opencode` and `.local/share/opencode` may contain real
provider credentials, MCP OAuth tokens, global config, plugins, skills,
sessions, snapshots, history, cache, logs, or other private state. Copy them
only into runs where you accept exposing that state.

## Preview ports

The regular `agent` service does not publish fixed host ports by default. If
OpenCode starts an app inside a run, publish only the port you need on that
command:

```bash
docker compose run --rm -p 127.0.0.1:3001:3000 agent
```

That maps host port `3001` to container port `3000` for that one session. Make
the app inside the container listen on `0.0.0.0`. On a VPS, expose
`0.0.0.0:HOST_PORT:CONTAINER_PORT` only when you really want public access.

## What's inside

- Debian trixie-slim base pinned by digest.
- Node.js 22 LTS + OpenCode CLI (`opencode-ai`).
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

Mount the project folder OpenCode should edit, and mount only the OpenCode data
you are willing to expose to that run.

## Customize

Edit `Dockerfile` and `compose.yml` directly. Add tools you reach for, flip on
stricter security flags (`read_only: true`, `cap_drop: [ALL]`, custom
`seccomp`), or swap the base image. After changing the image:

```bash
docker compose build --no-cache
```
