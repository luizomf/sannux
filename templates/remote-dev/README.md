# remote-dev

Generic Remote SSH target for local apps such as Claude Desktop, Claude Code,
Codex App, Antigravity, VS Code Remote SSH, Cursor-like IDEs, and other tools
that can connect to a Linux machine over SSH.

The app stays on your computer. Its remote server, shell commands, extensions,
caches, and project access run inside this container.

```txt
local app -> SSH -> sannux remote-dev container
                    /workspace
                    /home/agent
```

Use this template when you want one persistent remote environment for a local
app that does not fit the normal CLI-container flow. It is mainly a convenience
and isolation layer for third-party apps: the app UI stays local, while the
remote server, commands, cache, and project access stay inside the container.

Do not treat `remote-dev` as the default template for many parallel ephemeral
agents. You can create multiple copies, but each copy is a long-running SSH
environment with its own ports, SSH config, state, and resource usage. That gets
expensive and harder to operate quickly.

For disposable CLI agents, use a CLI template instead:

```bash
docker compose run --rm agent
```

## What this template gives you

- `Dockerfile`: OpenSSH server, Codex CLI, Node.js, Python, build tools, and
  common CLI helpers.
- `compose.yml`: a long-running `ssh` service under the `daemon` Compose
  profile, plus an auxiliary non-root `agent` shell.
- `setup-host.sh`: creates safe host folders, writes `.env`, generates a
  dedicated SSH key, updates the managed SSH config block, builds the image,
  starts SSH, and tests the connection.
- `sshd_config` and `sshd-entrypoint.sh`: key-only SSH login for the configured
  non-root user.

## Setup

From the repo root:

```bash
just setup remote-dev
```

The setup command:

- creates `templates/remote-dev/.env` when missing;
- fills safe local paths outside this repo when `WORKSPACE_PATH` and
  `AGENT_HOME_PATH` are empty;
- uses `agent` as the SSH user and writes that to the generated SSH config;
- configures Codex to use the container as its sandbox boundary;
- prepares Codex's app-server runtime directory for the in-container tmpfs;
- creates a dedicated SSH key under `~/.ssh/sannux/`;
- installs the public key into `${AGENT_HOME_PATH}/.ssh/authorized_keys`;
- adds a managed `sannux-remote-dev` entry to `~/.ssh/config`;
- removes stale entries for this template from `~/.ssh/sannux/known_hosts`;
- builds and starts the SSH container.

Then connect your app to:

```txt
sannux-remote-dev
```

Open this folder in the app:

```txt
/workspace
```

## Scenarios

### 1. Template

The template is a generic Remote SSH target, not a harness for one specific
agent CLI. Local apps such as Codex App, Antigravity, Claude Desktop, Claude
Code, VS Code Remote SSH, and similar tools connect over SSH and install or run
their own remote server inside the container.

This is the main exception to the CLI-template shape: `remote-dev` is designed
around one persistent SSH endpoint with stable ports and persistent state.

### 2. Initial persistent config

`.env` plus `setup-host.sh` creates the first working remote environment.

The setup script fills `WORKSPACE_PATH` and `AGENT_HOME_PATH` when they are
empty, but only with folders under `~/sannux-data`, outside this repository.
Those paths are mounted as `/workspace` and `/home/agent` in the container.

The persistent home stores SSH authorized keys, app auth/config, extensions,
caches, and any remote-server state written by connected apps.

### 3. Persistent TUI run

This template does not provide a persistent TUI agent run. The persistent
interactive surface is SSH:

```bash
ssh sannux-remote-dev
```

From an IDE or local app, connect to the same SSH host and open `/workspace`.

### 4. Persistent daemon run

This is the primary run mode:

```bash
docker compose --profile daemon up -d ssh
```

From the repo root:

```bash
just up remote-dev ssh
```

The `ssh` service keeps the same workspace, home, SSH host keys, app cache, and
preview ports across restarts.

### 5. One-shot run with persistent home

For diagnostics or a plain shell in the same mounted workspace and home:

```bash
docker compose run --rm agent
```

From the repo root:

```bash
just run remote-dev
```

This is only an auxiliary non-root shell. It is not a dedicated Codex, Claude,
Gemini, Pi, or opencode one-shot harness, and it does not publish the stable
preview ports from the `ssh` daemon service.

### 6. One-shot run with ephemeral home

`remote-dev` does not provide an ephemeral-home agent workflow. If you need many
disposable non-interactive agents, use a CLI template such as `codex`,
`codex-ollama`, `claude-code`, `claude-ollama`, `gemini`, `opencode`, or `pi`.

## Manual usage

Create both directories before running Compose. `WORKSPACE_PATH` and
`AGENT_HOME_PATH` must be absolute host paths outside this template folder and
outside the repository checkout.

```bash
install -m 0600 .env.example .env
# edit WORKSPACE_PATH and AGENT_HOME_PATH
# also create both folders, plus .codex/app-server-control under AGENT_HOME_PATH
docker compose build
docker compose --profile daemon up -d ssh
```

After configuring SSH keys, connect with:

```bash
ssh sannux-remote-dev
```

For a non-root shell without SSH, useful for diagnostics or an ad hoc session:

```bash
docker compose run --rm agent
```

That one-off `agent` service does not publish preview ports. The long-running
`ssh` service publishes SSH and the configured preview ports from `.env`
because Remote SSH apps need a stable endpoint. If you need a port only for a
temporary `agent` shell, publish it on that command:

```bash
docker compose run --rm -p 127.0.0.1:3001:3000 agent
```

## Security notes

- SSH binds to `127.0.0.1` by default.
- Password login is disabled.
- Root login is disabled.
- The SSH login user is `agent` by default.
- Advanced users may change `REMOTE_USER` before setup; the setup script writes
  the same user to `~/.ssh/config` so Remote SSH apps do not have to guess.
- Agent forwarding is disabled.
- TCP forwarding is enabled because Remote SSH apps commonly need it.
- `~/.codex/app-server-control` is mounted as tmpfs inside the container. Codex
  App uses a Unix socket there for SSH remote sessions; keeping that socket off
  host bind mounts avoids macOS filesystem permission edge cases.
- Codex is configured with `sandbox_mode = "danger-full-access"` inside the
  container. That avoids a fragile nested Linux sandbox. The container mount is
  the boundary, so keep `WORKSPACE_PATH` narrow.
- Do not mount your real home directory. Mount only the project folder you want
  the app to see.

On a VPS, prefer keeping the container SSH port private and reaching it through
the host SSH service, a tunnel, or a firewall rule you understand.

## What not to mount

Do not mount your real home directory, SSH keys, cloud credentials, package
manager tokens, global Git or GitHub config, or the Docker socket. Mount only
the project folder the remote app should see, and keep the persistent
`AGENT_HOME_PATH` dedicated to this SSH target.

## What's inside

- Debian trixie-slim base pinned by digest.
- OpenSSH server.
- Codex CLI.
- `bubblewrap`, required by Codex startup checks on Linux.
- Node.js 22 LTS.
- Python 3 + pip + venv.
- `build-essential` for native deps.
- CLI helpers: `git`, `rg`, `fd`, `jq`, `fzf`, `bat`, `tree`, `less`.
- Common archive helpers used by coding agents and remote apps.
