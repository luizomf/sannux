# pi

[Pi Coding Agent](https://pi.dev/docs/latest/quickstart) running in a
Debian-slim Docker container.

This template is intentionally small: configure one persistent workspace and one
persistent Pi home, authenticate once, then choose whether each run is
interactive, persistent one-shot, or ephemeral one-shot.

Real credentialed Pi runs have not been tested in this pass; the CLI contract
below is based on Pi's official docs and local `pi --help` behavior.

## Example Vídeo (PT-BR 🇧🇷)

Example using `codex-ollama` (in Brazilian Portuguese).

[![Agentes de IA Seguros no Docker](https://i3.ytimg.com/vi/wqe0VU5L5aU/maxresdefault.jpg)](https://youtu.be/wqe0VU5L5aU)

- [youtu.be/wqe0VU5L5aU](https://youtu.be/wqe0VU5L5aU)

## What this template gives you

- `Dockerfile`: Pi CLI plus common Linux development tools.
- `compose.yml`: Docker Compose service that mounts your project at `/workspace`
  and the agent home at `/home/agent`.
- `setup-host.sh`: creates host folders, writes safe `.env` defaults, and
  prepares Pi's persisted config directory.

Pi is installed from the npm package `@earendil-works/pi-coding-agent`.

## Setup

Copy the environment file:

```bash
install -m 0600 .env.example .env
```

Ideally, edit these values so the workspace and agent home are explicit:

```env
WORKSPACE_PATH=/srv/example-data/workspaces/my-project
AGENT_HOME_PATH=/srv/example-data/agent-homes/pi
```

If `WORKSPACE_PATH` and `AGENT_HOME_PATH` stay empty, `setup-host.sh` uses this
fallback:

```txt
~/sannux-data/workspaces/pi
~/sannux-data/agent-homes/pi
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
just setup pi
just run pi
```

## Scenarios

### 1. Template

The template is the harness-specific environment: `pi` means Pi Coding Agent
running with its own workspace and isolated agent home.

Other templates follow the same idea for other harnesses, such as Codex, Claude,
Gemini, Hermes, or opencode.

### 2. Initial persistent config

`.env` plus `setup-host.sh` creates the first working agent home.

Authenticate Pi with one of these options:

- set provider keys such as `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`,
  `GEMINI_API_KEY`, or `OPENROUTER_API_KEY` in `.env`;
- run the Pi TUI with `docker compose run --rm agent` and use `/login`;
- pass a one-command API key override with `--api-key` when that is acceptable.

Pi docs state that subscription login and API-key login store state under
`~/.pi/agent`. With this template, `PI_CODING_AGENT_DIR` is set to:

```txt
/home/agent/.pi/agent
```

On the host, that is:

```txt
${AGENT_HOME_PATH}/.pi/agent/
```

Expect this directory to hold private state such as `auth.json`,
`settings.json`, `models.json`, `sessions/`, `git/`, `npm/`, extensions, skills,
prompt templates, themes, package installs, logs, and other runtime state.

### 3. Persistent TUI run

Use this for normal interactive work:

```bash
docker compose run --rm agent
```

From the repo root:

```bash
just run pi
```

This run stays active until you quit Pi. It uses the persistent workspace and
persistent agent home from `.env`.

Pi loads context files at startup from the global Pi dir, parent directories,
and the current workspace. Project instructions can live in
`/workspace/AGENTS.md` or `/workspace/CLAUDE.md`; global instructions can live
in `${AGENT_HOME_PATH}/.pi/agent/AGENTS.md`.

### 4. Persistent daemon run

This template does not provide a Pi daemon service.

The official Pi CLI docs list interactive mode, print mode, JSON mode, RPC mode,
and HTML export. They do not document a long-running daemon with stable ports,
logs, and shutdown semantics. If a daemon profile is added later, document its
ports, auth, logs, and shutdown flow here.

### 5. One-shot run with persistent home

Use print mode when sharing the same agent home is acceptable:

```bash
docker compose run --rm -T agent -p "Summarize the mounted project."
```

With piped stdin:

```bash
cat README.md | docker compose run --rm -T agent -p "Summarize this file."
```

From the repo root:

```bash
echo "Summarize the mounted project." | just run pi -p
```

Pi docs describe `-p` / `--print` as print mode: Pi prints the response and
exits. In print mode, piped stdin is merged into the initial prompt.

For a read-only review, allow only read-oriented tools:

```bash
docker compose run --rm -T agent \
  --tools read,grep,find,ls \
  -p "Review the code and list risky files."
```

Pi intentionally has no built-in permission popups. The default tools can read,
write, edit, and run shell commands inside the mounted workspace. For unattended
runs, prefer a dedicated workspace, a git checkpoint, explicit `--tools`, and a
container home that exposes only the state needed for that run.

This is simple, but the run can read and write the full persistent
`AGENT_HOME_PATH`: auth, settings, sessions, packages, extensions, skills,
prompts, themes, logs, and other private runtime state.

### 6. One-shot run with ephemeral home

Use this when you want a fresh `/home/agent` for one command.

With provider API keys in `.env`, an empty temporary home should be enough:

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

Use `--no-session` when the command should not save a session file. This is
separate from the Docker-level ephemeral home: the temp home controls which Pi
auth/config/package state is exposed, and `--no-session` controls whether Pi
writes a session.

If you rely on `/login`, custom `models.json`, installed packages, extensions,
skills, prompts, themes, or global context from the persistent home, copy only
the state you accept exposing to the run:

```bash
persistent_home=/srv/example-data/agent-homes/pi
test -d "$persistent_home/.pi/agent"
rm -rf "$tmp_home/.pi/agent"
mkdir -p "$tmp_home/.pi"
cp -R "$persistent_home/.pi/agent" "$tmp_home/.pi/agent"
```

Short warning: Docker `-v` can create missing host folders. Create and inspect
the folders yourself when the path matters.

Another warning: `.pi/agent` may contain real provider credentials, OAuth
tokens, settings, sessions, package clones, installed npm packages, extensions,
skills, prompt templates, themes, logs, cache, and other private state. Copy it
only into runs where you accept exposing that state.

## Preview ports

The regular `agent` service does not publish fixed host ports by default. If Pi
starts an app inside a run, publish only the port you need on that command:

```bash
docker compose run --rm -p 127.0.0.1:3001:3000 agent
```

That maps host port `3001` to container port `3000` for that one session. Make
the app inside the container listen on `0.0.0.0`. On a VPS, use
`0.0.0.0:HOST_PORT:CONTAINER_PORT` only when you intentionally want to expose
the app.

## Ollama / local models

Pi supports custom providers through:

```txt
${AGENT_HOME_PATH}/.pi/agent/models.json
```

Minimal Ollama example for a server on the Docker host:

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

The `apiKey` field is required by Pi's model config shape, but Ollama ignores
the value.

If Ollama runs on another machine in your LAN, use that IP instead:

```json
"baseUrl": "http://203.0.113.10:11434/v1"
```

Then launch Pi and select the model with `/model`, or start directly:

```bash
docker compose run --rm agent --provider ollama --model example-coder-model:7b
```

## Recipes

From the repo root, with `just`:

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

From this template folder, without `just`:

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

## What's inside

- Debian trixie-slim base pinned by digest.
- Node.js 22 LTS + Pi Coding Agent (`@earendil-works/pi-coding-agent`).
- Python 3 + pip + venv.
- `build-essential` for projects with native deps.
- CLI helpers: `git`, `rg`, `fd`, `jq`, `fzf`, `bat`, `tree`, `less`.
- Non-root user `agent`, UID/GID matched to your host via build args.

## What's mounted

- `${WORKSPACE_PATH}` (host) -> `/workspace` (container): your project.
- `${AGENT_HOME_PATH}` (host) -> `/home/agent/` (container): Pi auth, config,
  sessions, packages, and other state.

The container itself is ephemeral (`--rm`). Destroy and recreate it without
losing state because both bind mounts survive on the host.

Both paths are required and should live outside the `sannux` checkout. This
prevents nested Git repositories and keeps agent credentials out of this repo.
Because the bind mounts do not auto-create host paths, missing directories fail
early instead of being created in the wrong place.

## What Not To Mount

Do not mount your real host home, SSH keys, cloud credentials, package manager
tokens, global git config, browser profiles, or other agent homes into this
container.

Use a dedicated workspace and a dedicated `AGENT_HOME_PATH` per Pi identity. For
one-shot ephemeral runs, copy only `.pi/agent` files that the command truly
needs, and remember that copied Pi state may include real auth and session
history.

## Security notes

Pi's docs are explicit: no permission popups by default. It expects you to use a
container, build your own confirmation flow, or add extensions if you need
stricter controls.

This template gives Pi a small house:

- it can see `/workspace`;
- it can see its own `/home/agent`;
- it can use the network;
- it cannot see your real host home unless you mount it.

That is still not a full security boundary against network exfiltration of the
workspace. It is a practical blast-radius reducer.

## Resource limits

The `.env` file exposes:

```env
MEM_LIMIT=4g
CPU_LIMIT=4
```

These are not security settings. They are only a brake for runaway commands,
heavy builds, or accidental loops. `MEM_LIMIT` caps container memory,
`CPU_LIMIT` caps CPU quota, and `pids_limit: 512` in `compose.yml` limits the
number of processes/threads. Tune the values to your VPS size.

## Customize

Edit `Dockerfile` and `compose.yml` directly. Add tools you reach for, adjust Pi
settings, or tighten Compose settings for your deployment. After changing
`Dockerfile`, run `just rebuild pi` from the repo root, or
`docker compose build --no-cache` from this template folder.
