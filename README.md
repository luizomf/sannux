# sannux

**Sandbox Linux**: Docker templates for running AI coding agents in isolated
containers.

The goal is simple: give the agent a useful Linux home, tools, and a project
folder, without giving it your real host home.

Current templates:

| Template        | What it runs                  | Best for                                         |
| --------------- | ----------------------------- | ------------------------------------------------ |
| `claude-code`   | Claude Code CLI               | Anthropic/Claude Code workflow                   |
| `claude-ollama` | Claude Code pointed at Ollama | Claude Code harness with a local/open model      |
| `codex`         | OpenAI Codex CLI              | Codex workflow with OpenAI login/API             |
| `codex-ollama`  | Codex CLI pointed at Ollama   | Codex harness with a local/open model            |
| `gemini`        | Gemini CLI                    | Google Gemini workflow                           |
| `hermes`        | Hermes Agent                  | messaging, webhooks, cron-like automations       |
| `opencode`      | opencode CLI                  | model-agnostic terminal agent workflow           |
| `pi`            | Pi Coding Agent               | terminal-first coding agent with local config    |
| `remote-dev`    | Single remote SSH server      | one remote environment for local Remote SSH apps |

Each template lives in `templates/<template>/` and is self-contained. You can
clone the whole repo and use the root `justfile`, or copy one template folder to
a VPS and use plain Docker Compose.

## Vídeo (PT-BR 🇧🇷)

[![Agentes de IA Seguros no Docker](https://i3.ytimg.com/vi/wqe0VU5L5aU/maxresdefault.jpg)](https://youtu.be/wqe0VU5L5aU)

- [youtu.be/wqe0VU5L5aU](https://youtu.be/wqe0VU5L5aU)

## Core concepts

These words have specific meanings in this repo:

- **Template**: a reusable environment definition: Dockerfile, Compose service,
  tools, entrypoint, resource limits, and default wiring. Examples: `codex`,
  `codex-ollama`, `claude-code`, and `remote-dev`.
- **Initial persistent config**: the first working agent home for a template. It
  usually comes from `.env` plus a setup script.
- **Run**: one concrete execution of a template, with a workspace, an agent
  home, a command, logs, and an exit status. A run can be interactive, one-shot,
  scheduled, or long-running.
- **Agent home**: the host directory mounted at `/home/agent` for a run. It is
  where the CLI can write runtime state such as auth, config, sessions, logs,
  cache, memory, and local history.
- **Persistent agent**: an agent identity that reuses the same agent home across
  runs. This is useful for TUI sessions, manual login, and work where keeping
  state is intentional.
- **Ephemeral run**: a run with a temporary agent home created from a template
  config. It is useful for unattended YOLO-style automation, cron jobs, and
  overlapping runs that should not share the full CLI home.
- **Daemon service**: a long-lived service managed through Compose, such as
  `remote-dev` SSH, Hermes `gateway`/`dashboard`, or Claude Code
  `remote-control`. It has a service lifecycle: `up`, `logs`, `stop`, stable
  ports, and persistent state.

A template defines how to run. The initial config gives you one working agent
home. A run is one execution. A daemon service stays alive.

The full cross-template contract lives in
[docs/template-contract.md](docs/template-contract.md). Run `just check` before
finishing template or contract documentation changes; it validates structure,
not your local values.

When the distinction matters, avoid using `agent` by itself. Prefer precise
terms like `CLI agent`, `TUI session`, `ephemeral run`, `persistent agent`,
`daemon service`, and `agent home`.

## Table of Contents

- [1. The idea](#1-the-idea)
- [2. What this protects](#2-what-this-protects)
- [3. The two folders that matter](#3-the-two-folders-that-matter)
- [4. First run with Codex](#4-first-run-with-codex)
- [5. Using just](#5-using-just)
- [6. Using plain Docker Compose](#6-using-plain-docker-compose)
- [7. One-shot commands](#7-one-shot-commands)
- [8. Local models with Ollama](#8-local-models-with-ollama)
- [9. Long-running agents and Compose profiles](#9-long-running-agents-and-compose-profiles)
- [10. Sharing one workspace between agents](#10-sharing-one-workspace-between-agents)
- [11. UID/GID and file ownership](#11-uidgid-and-file-ownership)
- [12. Resource caps](#12-resource-caps)
- [13. Template map](#13-template-map)
- [14. Troubleshooting](#14-troubleshooting)
- [15. Hardening ideas](#15-hardening-ideas)

## 1. The idea

AI coding agents are powerful and obedient. That is useful, but it also means a
bad prompt, a compromised dependency, or a prompt injection can make the agent
do exactly the wrong thing very quickly.

Running an agent directly on your laptop or VPS usually gives it the same
filesystem access your user has:

- your real home directory;
- SSH keys;
- GitHub credentials;
- cloud config;
- shell history;
- random projects you did not mean to expose;
- secrets scattered in local dotfiles.

`sannux` puts the agent in a container and mounts only two explicit host
folders:

- a **workspace** mounted at `/workspace`;
- an **agent home** mounted at `/home/agent`.

The agent can still work like a normal coding assistant. It can read and edit
the project in `/workspace`, install packages inside the container, keep its own
login state in `/home/agent`, run shell commands, and talk to model providers.
It just does not get your real host home by accident.

Think of each template as the shape of a small Linux box. Each run decides which
workspace and agent home that box receives.

## 2. What this protects

This is not maximum-security container hardening. It is practical isolation for
agentic coding workflows.

**It helps protect against:**

- the agent deleting or modifying files outside the mounted workspace;
- the agent reading `~/.ssh`, `~/.aws`, `~/.config/gh`, `.npmrc`, shell history,
  or other host credentials;
- accidental nested Git repositories inside this repo;
- one agent seeing another agent's auth/config/history;
- runaway commands consuming too much memory or CPU.

**It does not protect against:**

- network exfiltration of files inside the mounted workspace;
- malicious code inside the project you intentionally mounted;
- compromised base images or compromised agent binaries;
- kernel/container escape vulnerabilities;
- a model making bad decisions inside the access you gave it.

The baseline is: keep the agent out of your real home, keep each agent's state
separate, and make the risky path explicit.

### Why not Docker Sandboxes (`sbx`)?

[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) is a good fit when you
want stronger isolation for autonomous agents: it runs sandboxes in microVMs,
gives each sandbox its own Docker daemon, and adds policy and credential
handling around network access.

`sannux` does not try to replace that. It intentionally stays on plain Docker
Compose templates because the project goal is different:

- templates are easy to inspect, copy to a VPS, and run with standard Docker
  Compose;
- the runtime avoids the overhead of a per-sandbox VM plus a private Docker
  daemon;
- there is no Docker account login, `sbx` installation, or KVM/hypervisor setup
  in the happy path;
- agent homes, workspaces, ports, tools, and provider config stay explicit in
  files users can edit.

The two approaches can also stack. You can use `sbx` as the stronger outer
boundary and still run Docker/Compose workloads inside it when repeatable
container packaging is useful. That is the better shape for critical repos, runs
with many secrets, or unattended agents that need broad freedom. It buys more
isolation, but also adds another runtime layer and more moving parts.

Use `sbx`, another microVM-based sandbox, or a remote disposable VM when you
need a stronger boundary, especially if the agent must build and run nested
containers with broad autonomy or handle sensitive credentials. Use `sannux`
when you want practical, auditable, copyable Docker templates and you accept
normal container isolation as the boundary.

## 3. The two folders that matter

Every template requires these `.env` values:

```env
WORKSPACE_PATH=/absolute/path/to/the/project
AGENT_HOME_PATH=/absolute/path/to/this/agent/home
```

Inside the container they become:

```txt
WORKSPACE_PATH  -> /workspace
AGENT_HOME_PATH -> /home/agent
```

Use paths outside this repository.

Good:

```txt
/srv/example-data/workspaces/my-app
/srv/example-data/agent-homes/codex
```

Also fine for local testing:

```txt
/home/example/sannux-data/codex/workspace
/home/example/sannux-data/codex/home
```

Avoid:

```txt
$HOME/path/to/sannux/templates/codex/workspace
$HOME/path/to/sannux/.agent-home
$HOME
~
/
```

Why so strict?

The workspace is what the agent is allowed to edit. The agent home is where the
CLI stores login tokens, config, sessions, logs, memory, and local history. TUI
sessions and manual login normally use a persistent agent home. Automation that
runs with broad permissions should prefer an ephemeral agent home based on a
known-good template config. If these folders live inside the repo, it becomes
very easy to accidentally commit state, credentials, caches, or a repository
inside a repository.

### Temporary workspace override

For quick local experiments, you can run the same template against another
workspace without editing `.env` or creating a new template copy. Create the
target directory first, then override only `/workspace` for that command:

```bash
mkdir -p /tmp/sannux-example-workspace
just compose pi run -v /tmp/sannux-example-workspace:/workspace --rm -it agent
```

That override is command-scoped: `WORKSPACE_PATH` in `.env` is unchanged, and
the agent still uses the same persisted `AGENT_HOME_PATH` for auth/config/state.

Use this intentionally. The short `-v host:container` form is Docker's direct
bind-mount syntax, so it bypasses the template's `create_host_path: false` guard
and Docker may create a missing host path for you. Prefer an existing absolute
path, and do not mount your real home directory, `/`, SSH keys, cloud
credentials, or the Docker socket.

For a one-shot run, `-v` is often enough: point `/workspace` and `/home/agent`
at the host folders you want for that command.

### Command-scoped preview ports

Ephemeral CLI templates do not publish fixed host ports by default. If an agent
starts a frontend, backend, or throwaway HTTP server, publish only the port you
need for that run:

```bash
cd templates/codex
docker compose run --rm -p 127.0.0.1:3001:3000 agent
```

That maps `127.0.0.1:3001` on the Docker host to port `3000` inside that one
container. Pick any host/container pair that fits the app:

```bash
docker compose run --rm -p 127.0.0.1:8001:8000 agent
docker compose run --rm -p 127.0.0.1::3000 agent  # random host port
```

If you start an app inside the container, bind the app to `0.0.0.0`, not only
`localhost`, so Docker can forward traffic to it. On a VPS, use
`0.0.0.0:HOST_PORT:CONTAINER_PORT` only when you intentionally want to expose
the app, and put a firewall or reverse proxy in front.

Daemon-style templates such as `remote-dev`, Claude Code `remote-control`, and
Hermes `gateway`/`dashboard` still declare their own long-running ports in
Compose, because those services are meant to be stable remote endpoints.

## 4. First run with Codex

The examples below use Codex because it is easy to demonstrate. The same folder
layout applies to all templates.

From the repo root:

```bash
just init codex
```

Ideally, edit `templates/codex/.env`:

```env
USER_UID=1000
USER_GID=1000
WORKSPACE_PATH=/srv/example-data/workspaces/my-project
AGENT_HOME_PATH=/srv/example-data/agent-homes/codex
SANNUX_TERM=xterm-256color
SANNUX_COLORTERM=truecolor
# Optional for API key users:
# OPENAI_API_KEY=sk-...
MEM_LIMIT=4g
CPU_LIMIT=4
```

Create the host folders and fill safe defaults under `~/sannux-data` if
`WORKSPACE_PATH` or `AGENT_HOME_PATH` stayed empty:

```bash
just setup codex
```

Validate the Compose config and run:

```bash
just config codex
just run codex
```

For API key users, uncomment `OPENAI_API_KEY` in `templates/codex/.env` and run
normally. No Codex login is needed.

For OAuth/subscription users, Codex asks you to log in on first run. The auth
screen has three choices. Inside Docker, use **Sign in with Device Code**; do
not use **Sign in with ChatGPT**, because that path assumes a local desktop
browser. The auth file is written under:

```txt
${AGENT_HOME_PATH}/.codex/
```

When you exit, the container is removed because the default command uses
`docker compose run --rm`. Your workspace and agent home remain on the host.

Run it again:

```bash
just run codex
```

The container is new, but the agent state is still there because
`AGENT_HOME_PATH` was mounted again.

## 5. Using just

`just` is only a convenience wrapper for people who cloned the whole repo. It
does not do anything magical.

List recipes:

```bash
just
```

Create a template `.env` from `.env.example`:

```bash
just init codex
```

Run a template-specific setup helper when one exists:

```bash
just setup remote-dev
```

Render and validate the Compose config:

```bash
just config codex
```

Build a template:

```bash
just build codex
```

Rebuild without cache:

```bash
just rebuild codex
```

Run the agent interactively:

```bash
just run codex
```

Open a shell inside the same container image:

```bash
just shell codex
```

Open a root shell for debugging the image:

```bash
just root-shell codex
```

Treat root-shell changes as disposable. If you install packages or change files
outside mounted volumes, those changes disappear with the ephemeral container;
make real fixes in the Dockerfile and rebuild.

The everyday loop is intentionally small. Example with Claude Code:

```bash
just setup claude-code      # create .env and safe host folders
just run claude-code        # start a fresh interactive container
```

Replace `claude-code` with any template name from `just templates`.

To add more tools to an image, edit that template's `Dockerfile`, then rebuild.
For example:

```bash
just rebuild claude-code
```

Stop and remove Compose containers/networks/volumes for a template:

```bash
just down codex
```

For daemon services, such as Claude Code Remote Control, Hermes gateway, Hermes
dashboard, or the Remote SSH service:

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

If a recipe says the `.env` file is missing, create it first:

```bash
just init codex
```

### Remote SSH apps

Use `remote-dev` when the app stays on your computer but needs one Linux SSH
target for its commands and remote server. This is the shape used by apps such
as Claude Desktop, Claude Code, Codex App, Antigravity, VS Code Remote SSH, and
similar tools.

It is a convenience and isolation layer for third-party apps that do not run as
simple CLI containers. It gives those apps a single remote environment with one
workspace and one persistent home.

Unlike the CLI templates, `remote-dev` is daemon-first: the main service is the
long-running `ssh` service under the `daemon` Compose profile. The `agent`
service is only an auxiliary non-root shell for diagnostics or ad hoc work.

The easiest path is:

```bash
just setup remote-dev
```

That command creates a dedicated SSH key, writes a managed `sannux-remote-dev`
entry to `~/.ssh/config` with the `agent` user, prepares Codex's app-server
runtime directory, builds the image, and starts the SSH service.

In the app, connect to:

```txt
sannux-remote-dev
```

Then open:

```txt
/workspace
```

The persistent home stays on the host, but `~/.codex/app-server-control` runs
from an in-container tmpfs so Codex App's SSH app-server socket works on Docker
Desktop for macOS.

The app runs locally. Its remote server, commands, cache, and project access run
inside the container.

`remote-dev` is not the best default for many parallel ephemeral agents. You can
create multiple remote-dev copies, but each one is a long-running SSH
environment with its own ports, SSH config, state, and resource usage. That gets
expensive and harder to manage quickly. For disposable CLI agents, prefer the
agent templates with:

```bash
docker compose run --rm agent
```

## 6. Using plain Docker Compose

If you copied only one template folder to a VPS, use Docker Compose directly.

Example with `templates/codex`:

```bash
cd templates/codex
install -m 0600 .env.example .env
mkdir -p /srv/example-data/workspaces/my-project
mkdir -p /srv/example-data/agent-homes/codex
# edit .env
docker compose build
docker compose run --rm agent
```

Publish a preview port for an interactive `run` session:

```bash
docker compose run --rm -p 127.0.0.1:3001:3000 agent
```

Use any host/container port pair you need for that one session. For example,
`-p 127.0.0.1:8001:8000` maps host port `8001` to container port `8000`.

Equivalent shell access:

```bash
docker compose run --rm --entrypoint bash agent
```

Equivalent root shell access for debugging:

```bash
docker compose run --rm --user root --entrypoint bash agent
```

Clean up the Compose project:

```bash
docker compose down -v
```

This does not delete `WORKSPACE_PATH` or `AGENT_HOME_PATH`, because both are
host bind mounts.

## 7. One-shot commands

Interactive TUIs are good for humans. For automation, stdin is usually easier.
The low-level `just run` and `docker compose run` examples below use the
template's configured `AGENT_HOME_PATH`. That is convenient, but for unattended
YOLO-style automation it also means the command can read and write the same
auth, sessions, logs, caches, and history as your TUI.

For `codex-ollama`, use the persistent home when sharing the TUI state is OK:

```bash
cd templates/codex-ollama
echo "Summarize the mounted project and list risky files." \
  | docker compose run --rm -T agent exec - --ephemeral --yolo
```

Use a temporary home when you only want to expose the Codex config you accept
for that run:

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

Docker `-v` can create missing host folders, and `.codex` may contain auth or
API state. Mount only what you accept exposing to that run.

Codex from the repo root:

```bash
printf '%s\n' "Summarize the mounted project and list risky files." | \
  just compose codex run --rm -T agent exec \
    --ephemeral --dangerously-bypass-approvals-and-sandbox -
```

Codex from the template folder:

```bash
cd templates/codex
printf '%s\n' "Summarize the mounted project and list risky files." | \
  docker compose run --rm -T agent exec \
    --ephemeral --dangerously-bypass-approvals-and-sandbox -
```

Gemini from the repo root:

```bash
just run gemini -p "summarize the mounted project"
```

For Gemini, stdin is appended to the `-p` prompt. Use `-p` alone unless you
intentionally want to merge stdin context with the prompt.

OpenCode from the repo root:

```bash
just run opencode run "Summarize the mounted project and list risky files."
```

OpenCode uses `opencode run [message..]` for non-interactive automation.
Configure `permission` in `opencode.json` when a run should ask or deny reads,
edits, shell commands, or external directory access. Real credentialed OpenCode
runs have not been tested yet; PRs with verified provider-specific notes are
welcome. For unattended write tasks, local `opencode run --help` also exposes
`--dangerously-skip-permissions`; keep explicit `deny` rules for anything the
run must never do.

Pi from the repo root:

```bash
echo "Summarize the mounted project and list risky files." | just run pi -p
```

Claude Code with Anthropic auth from the template folder, using the persistent
home:

```bash
cd templates/claude-code
echo "Summarize the mounted project and list risky files." \
  | docker compose run --rm -T agent \
    --dangerously-skip-permissions --no-session-persistence -p -
```

Use a temporary home when you want a fresh `/home/agent` while reusing the
Claude state files prepared by `just setup claude-code`:

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

For real Claude Code auth, `.claude` and `.claude.json` can contain login,
trusted projects, hooks, MCP config, and other private state. Copy them only
into runs where you accept exposing that state.

Claude Code with Ollama from the template folder, using the persistent home:

```bash
cd templates/claude-ollama
echo "Summarize the mounted project and list risky files." \
  | docker compose run --rm -T agent \
    --dangerously-skip-permissions --no-session-persistence -p -
```

Use a temporary home when you want a fresh `/home/agent` while reusing the
Claude state files prepared by `just setup claude-ollama`:

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

For Claude/Ollama, you can also override the workspace for one command:

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

That command still uses the persistent agent home from `.env`; only `/workspace`
is replaced for that run.

The important detail is `-T` with Docker Compose when piping input. It disables
TTY allocation for that run, which makes stdin behave like normal automation.
After the command prints its response, the `--rm` container exits and is
removed.

## 8. Local models with Ollama

The `*-ollama` templates split the stack in two:

- the **agent harness** runs inside Docker;
- the **model** runs in Ollama somewhere else.

This is useful because the harness brings terminal/file tools, while Ollama
serves a local or open-weight model.

### Same machine as Docker

If Ollama runs on the same host where Docker runs:

```env
OLLAMA_BASE_URL=http://host.docker.internal:11434/v1
```

For Claude-compatible templates:

```env
ANTHROPIC_BASE_URL=http://host.docker.internal:11434
```

### Another machine on the LAN

If Ollama runs on another machine:

```env
OLLAMA_BASE_URL=http://192.0.2.50:11434/v1
```

For Claude-compatible templates:

```env
ANTHROPIC_BASE_URL=http://192.0.2.50:11434
```

Use the real IP of the machine that runs Ollama.

### Codex Ollama model catalog

Codex CLI expects model metadata: context window, reasoning support, tool
support, and related behavior flags. Local Ollama model names are not in Codex's
built-in catalog, so `templates/codex-ollama/` ships a default catalog:

```txt
model_catalog.json
```

The compose file mounts a catalog file read-only:

```txt
${CODEX_MODEL_CATALOG_HOST_PATH:-./model_catalog.json} -> ${CODEX_MODEL_CATALOG_PATH:-/opt/sannux/model_catalog.json}
```

Leave `CODEX_MODEL_CATALOG_HOST_PATH` empty to use the shipped file. Set it to
an absolute host file path when the catalog is personal or machine-specific:

```env
CODEX_MODEL_CATALOG_HOST_PATH=/srv/example-data/model-catalogs/ollama_models.json
CODEX_MODEL_CATALOG_PATH=/opt/sannux/model_catalog.json
```

`CODEX_MODEL_CATALOG_PATH` is the path inside the container and the value
written into Codex config. It is not the host file path.

The same template also ships `codex-config.toml.template`. Run:

```bash
just setup codex-ollama
```

to render `${AGENT_HOME_PATH}/.codex/config.toml`. Codex loads that config for
both interactive runs and `codex exec`, so one-shot commands can stay short.

If you change:

```env
CODEX_MODEL=local-model:8b
```

also update the matching `slug` in the selected catalog file.

If the catalog says the model has a larger context than Ollama actually serves,
Codex will plan around a context window that does not really exist. Keep the
catalog honest.

## 9. Long-running agents and Compose profiles

Most templates are interactive:

```bash
docker compose run --rm agent
```

When you exit the CLI, the container stops and is removed. That is perfect for
coding sessions.

Some templates also have a real 24/7 mode. Claude Code can run Remote Control in
the background, Hermes can keep messaging, webhooks, and scheduled jobs alive
through its `gateway` process, Hermes can run its browser dashboard, and
`remote-dev` can keep an SSH target running. Because those services can receive
commands while you are away, treat access URLs, SSH keys, messaging allowlists,
dashboard access, and command approvals as part of the deployment, not as
optional polish.

Those services are hidden behind a Compose profile:

```yaml
profiles: ['daemon']
```

Profiles are optional groups of services. Docker Compose does not start them
unless you explicitly ask.

Start Claude Code Remote Control:

```bash
just up claude-code remote-control
```

The `remote-control` service runs `claude -n main-session --remote-control` in
the background. It is useful for VPS/mobile workflows where you want a
persistent Claude Code session URL. The image also includes `tmux` so that
manager-style Claude sessions can launch and inspect parallel child sessions
inside the same sandbox.

Start Hermes gateway:

```bash
just up hermes gateway
```

Start Hermes dashboard:

```bash
just up hermes dashboard
```

Start remote-dev SSH:

```bash
just up remote-dev ssh
```

The Claude Code `remote-control` service, Hermes gateway/dashboard, and
remote-dev SSH service publish their configured daemon preview ports. That lets
apps started from browser/phone-driven agent sessions, the Hermes dashboard, or
Remote SSH clients stay reachable through stable host ports. Regular `run --rm`
sessions stay portless unless you add `-p` to that specific command.

The Hermes dashboard binds to `127.0.0.1` on the host by default. Treat it as
sensitive because it can manage Hermes config and API keys.

Without `just`, for Claude Code:

```bash
cd templates/claude-code
docker compose --profile daemon up -d remote-control
```

Without `just`, for Hermes:

```bash
cd templates/hermes
docker compose --profile daemon up -d gateway
docker compose --profile daemon up -d dashboard
```

Without `just`, for remote-dev:

```bash
cd templates/remote-dev
docker compose --profile daemon up -d ssh
```

Check them:

```bash
just ps claude-code
just logs claude-code remote-control
just ps hermes
just logs hermes gateway
just logs hermes dashboard
just ps remote-dev
just logs remote-dev ssh
```

Stop them:

```bash
just down claude-code
just down hermes
just down remote-dev
```

Without `just`, for Claude Code:

```bash
cd templates/claude-code
docker compose stop remote-control
```

Without `just`, for Hermes:

```bash
cd templates/hermes
docker compose stop gateway
docker compose stop dashboard
```

Without `just`, for remote-dev:

```bash
cd templates/remote-dev
docker compose stop ssh
```

Use the mental model:

```txt
run --rm agent       -> temporary session; exits when the TUI exits
run --rm agent ...   -> one-shot command; exits after the response
--profile daemon up  -> background service that should stay alive
```

The Hermes dashboard is also a daemon-profile service. It runs the compiled
upstream dashboard on port `9119` inside the container and publishes it to
`${PORT_BIND_ADDRESS}:${HOST_PORT_DASHBOARD}` on the host.

## 10. Sharing one workspace between agents

You can point multiple agents at the same `WORKSPACE_PATH`.

Example:

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

That lets two agents work on the same project while keeping their own login
tokens, settings, logs, memory, and sessions separate.

This is the recommended shape:

```txt
same workspace, separate homes
```

Avoid:

```txt
same workspace, same agent home
```

Separate homes limit accidental leakage between agents. If one harness stores
something odd in its home, the other agent does not inherit it.

One practical warning: two agents editing the same files at the same time can
still conflict. Use Git, commits, branches, or clear task boundaries when doing
parallel work.

## 11. UID/GID and file ownership

Every template builds a non-root user named `agent`. These values control that
user's numeric identity:

```env
USER_UID=1000
USER_GID=1000
```

On Linux, this matters. Files created in a bind mount keep numeric ownership.
Set these to your host user:

```bash
id -u
id -g
```

On many Linux servers, you will get:

```env
USER_UID=1000
USER_GID=1000
```

On macOS, values can look different:

```env
USER_UID=501
USER_GID=20
```

Docker Desktop translates a lot of this for you on macOS, so ownership is less
painful there. Still, keeping the real numbers in `.env` makes examples more
portable and avoids surprises when moving the template to Linux.

If you change `USER_UID` or `USER_GID`, rebuild the image:

```bash
just rebuild codex
```

or:

```bash
docker compose build --no-cache
```

## 12. Resource caps

Each template exposes:

```env
MEM_LIMIT=4g
CPU_LIMIT=4
```

And the compose files include:

```yaml
mem_limit: ${MEM_LIMIT:-4g}
cpus: ${CPU_LIMIT:-4}
pids_limit: 512
```

These are not a security boundary. They are protection against accidents:

- runaway loops;
- dependency installs that explode;
- build commands using too much memory;
- too many child processes.

On a VPS, tune them to the machine size. On Docker Desktop, they still help, but
the real ceiling also depends on Docker Desktop's VM resource allocation.

Hermes defaults to more memory because the image and optional extras are
heavier:

```env
MEM_LIMIT=8g
CPU_LIMIT=4
```

## 13. Template map

Use this as the quick choice table.

### `codex`

Use when you want OpenAI Codex CLI with OpenAI auth.

First run:

```bash
just setup codex
just run codex
```

Device-code login:

```bash
cd templates/codex
docker compose run --rm agent login --device-auth
```

API key users can skip that login step by setting `OPENAI_API_KEY` in
`templates/codex/.env`, or by choosing the API key option in the Codex prompt.

One-shot:

```bash
printf '%s\n' "Review this project." | \
  just compose codex run --rm -T agent exec \
    --ephemeral --dangerously-bypass-approvals-and-sandbox -
```

### `codex-ollama`

Use when you want the Codex harness with an Ollama-served model.

Important `.env` values:

```env
OLLAMA_BASE_URL=http://192.0.2.50:11434/v1
CODEX_MODEL=local-model:8b
CODEX_MODEL_CATALOG_HOST_PATH=/srv/example-data/model-catalogs/ollama_models.json
```

Run `just setup codex-ollama` after editing `.env`; it writes the persisted
Codex config used by the TUI and by `codex exec`. For one-shot runs, either use
the same agent home or mount a temporary `/home/agent` with only the `.codex`
folder you accept exposing.

If the model changes, update the catalog selected by
`CODEX_MODEL_CATALOG_HOST_PATH`, or the template's `model_catalog.json` when
using the default.

### `claude-code`

Use when you want Claude Code with Anthropic auth. It also has an optional
Remote Control service for persistent VPS/mobile workflows.

First setup:

```bash
just setup claude-code
just run claude-code
```

Claude stores auth and config under the agent home, not your real host home. TUI
and Remote Control share the same `WORKSPACE_PATH` and `AGENT_HOME_PATH`. For
one-shot ephemeral runs, copy only `.claude` and `.claude.json` into the
temporary home when you accept exposing that Claude state.

Remote Control:

```bash
just up claude-code remote-control
just logs claude-code remote-control
just down claude-code
```

### `claude-ollama`

Use when you want Claude Code's harness pointed at an Ollama server exposing an
Anthropic-compatible API.

First setup:

```bash
just setup claude-ollama
just run claude-ollama
```

Important `.env` values:

```env
ANTHROPIC_BASE_URL=http://192.0.2.50:11434
ANTHROPIC_AUTH_TOKEN=ollama
ANTHROPIC_API_KEY=
ANTHROPIC_MODEL=example-ollama-model
```

One-shot:

```bash
cd templates/claude-ollama
echo "Review this project." \
  | docker compose run --rm -T agent \
    --dangerously-skip-permissions --no-session-persistence -p -
```

### `gemini`

Use when you want Google's Gemini CLI.

Auth options:

- `GEMINI_API_KEY`;
- Google OAuth stored in the agent home;
- Vertex AI config.

First setup:

```bash
just setup gemini
just run gemini
```

Prompt mode:

```bash
just run gemini -p "summarize the mounted project"
```

For one-shot write tasks, use `--yolo` or `--approval-mode yolo` explicitly.
Without it, Gemini may try to edit for a long time and then stop because the
non-interactive run cannot grant approval.

### `hermes`

Use when you want Hermes Agent, especially for messaging/webhooks/scheduled
jobs.

Hermes can call other agent CLIs when you add them to the image, but this
template does not bundle Codex, Claude Code, Gemini, Pi, opencode, or every
other possible delegate tool. Install the ones you need in
`templates/hermes/Dockerfile`, rebuild, and keep their auth scoped to the Hermes
agent home or this template's `.env`.

First setup:

```bash
just setup hermes
just run hermes setup
just run hermes
```

24/7 gateway:

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

Use when you want opencode's model-agnostic CLI.

First run:

```bash
just setup opencode
just run opencode
```

Provider login:

```bash
just run opencode auth login
```

One-shot:

```bash
just run opencode run "Summarize the mounted project."
```

### `pi`

Use when you want Pi Coding Agent.

First run:

```bash
just setup pi
just run pi
```

One-shot / print mode:

```bash
echo "Summarize the mounted project." | just run pi -p
```

Pi also supports local model configuration through its own persisted config
under:

```txt
${AGENT_HOME_PATH}/.pi/agent/
```

Pi does not provide a daemon service in this template. For non-interactive runs,
use `-p` / `--print`; use `--tools read,grep,find,ls` for read-only reviews, or
`--no-session` when a one-shot run should not write a session file.

### `remote-dev`

Use when you want one generic SSH target for local apps with Remote SSH support,
instead of a preinstalled CLI agent. Good examples are Claude Desktop, Claude
Code, Codex App, Antigravity, VS Code Remote SSH, and similar apps that need to
install a remote server or run commands over SSH.

This template is for one persistent remote environment: one workspace, one agent
home, one SSH service. It is useful for convenience and isolation around
third-party apps, not for launching many parallel disposable agents.

The long-running `ssh` service is the real remote-dev mode. The `agent` service
is just a non-root shell and is not a provider-specific one-shot harness.

For ephemeral CLI agents, use the CLI templates instead:

```bash
docker compose run --rm agent
```

One-command setup:

```bash
just setup remote-dev
```

Then connect the app to:

```txt
sannux-remote-dev
```

Codex App stores its SSH app-server socket under `~/.codex/app-server-control`;
`remote-dev` keeps that runtime directory on an in-container tmpfs while the
rest of the agent home remains persistent.

## 14. Troubleshooting

### `WORKSPACE_PATH is missing a value`

Docker Compose did not receive a workspace path. Some templates, such as
`codex`, `codex-ollama`, `claude-code`, `claude-ollama`, and `remote-dev`, can
fill a safe fallback when you run their setup script first.

Fix:

```bash
install -m 0600 .env.example .env
# edit .env, or run the template setup script when documented
```

### `bind source path does not exist`

The compose files intentionally use:

```yaml
create_host_path: false
```

This prevents Docker from silently creating the wrong folder for you.

Create the folders yourself:

```bash
mkdir -p /srv/example-data/workspaces/my-project
mkdir -p /srv/example-data/agent-homes/codex
```

### Files are owned by the wrong user on Linux

Set `USER_UID` and `USER_GID` to your host user and rebuild:

```bash
id -u
id -g
just rebuild codex
```

### TUI colors look wrong

The templates set:

```env
SANNUX_TERM=xterm-256color
SANNUX_COLORTERM=truecolor
```

If a CLI still refuses colors, try:

```env
SANNUX_FORCE_COLOR=1
```

This can make piped output noisier, so it is commented out by default.

### Ollama URL does not work

Use `/v1` for OpenAI-compatible clients:

```env
OLLAMA_BASE_URL=http://192.0.2.50:11434/v1
```

Do not use `/v1` for Anthropic-compatible Claude Code settings:

```env
ANTHROPIC_BASE_URL=http://192.0.2.50:11434
```

`host.docker.internal` is for the Docker host. If Ollama runs on another
machine, use that machine's LAN IP.

### The agent cannot see my project

Inside the container, the project is always:

```txt
/workspace
```

Check what you mounted:

```bash
just shell codex
pwd
ls -la /workspace
```

### I closed the terminal and the agent stopped

That is expected for:

```bash
docker compose run --rm agent
```

For Hermes 24/7 automation, use:

```bash
just up hermes gateway
```

### Can I mount my real home?

Technically yes. Do not do it for this project.

The point of these templates is to avoid giving an autonomous coding agent your
real home directory by accident.

## 15. Hardening ideas

The base templates are intentionally usable before they are paranoid. Good next
steps for stricter environments:

- network egress allow-listing;
- `cap_drop: [ALL]`;
- read-only root filesystem plus explicit writable mounts;
- custom seccomp/AppArmor profiles;
- separate Docker networks per agent;
- no provider keys in `.env`, only short-lived tokens;
- image pinning and vulnerability scanning;
- separate Linux users on the host for different agent families;
- microVMs when container isolation is not enough.

Do not add all of this blindly. Each layer has a usability cost. The default
project stance is practical isolation first, then stricter controls where the
risk justifies the friction.

## License

[MIT](./LICENSE).
