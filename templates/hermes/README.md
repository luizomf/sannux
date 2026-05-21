# hermes

[Hermes Agent](https://github.com/NousResearch/hermes-agent) running in Docker.
Hermes is not only a terminal agent: it can also run a 24/7 gateway for
messaging, webhooks, scheduled work, and a local web dashboard.

This template keeps Hermes inside a Debian-slim container with a non-root user,
your code mounted at `/workspace`, and Hermes auth/config/state persisted to an
explicit host agent home.

## What this template gives you

- `Dockerfile`: Hermes Agent plus common Linux development tools.
- `compose.yml`: an interactive `agent` service plus daemon-profile `gateway`
  and `dashboard` services.
- `setup-host.sh`: creates the host folders, writes safe `.env` defaults, and
  prepares `${AGENT_HOME_PATH}/.hermes`.
- `HERMES_HOME=/home/agent/.hermes`: Hermes state lands inside the mounted agent
  home, not inside the image layer.
- Hermes' managed Python venv is on `PATH`, so `python` is available inside the
  container while dependencies remain image-managed.
- Optional delegate CLIs such as Codex, Claude Code, Gemini, Pi, or opencode are
  not bundled. Add only the tools you actually want Hermes to call.

## Setup

Copy the environment file:

```bash
install -m 0600 .env.example .env
```

Ideally, edit these values so the workspace and agent home are explicit:

```env
WORKSPACE_PATH=/srv/example-data/workspaces/my-project
AGENT_HOME_PATH=/srv/example-data/agent-homes/hermes
```

If `WORKSPACE_PATH` and `AGENT_HOME_PATH` stay empty, `setup-host.sh` uses this
fallback:

```txt
~/sannux-data/workspaces/hermes
~/sannux-data/agent-homes/hermes
```

Create the host folders and fill missing `.env` values:

```bash
./setup-host.sh
```

Run the Hermes setup wizard, then test the TUI once:

```bash
docker compose run --rm agent setup
docker compose run --rm agent
```

From the repo root, the same flow is:

```bash
just setup hermes
just run hermes setup
just run hermes
```

Use `hermes setup` for the full wizard, `hermes model` when you only need
provider/model/auth configuration, and `hermes gateway setup` only after a
normal CLI chat works.

If you use a custom OpenAI-compatible endpoint, keep the provider key in this
template's `.env` or paste it through the Hermes setup/model wizard. Do not put
shared cloud, GitHub, npm, or SSH credentials in the mounted workspace.

## Scenarios

### 1. Template

The template is the harness-specific environment: `hermes` means Hermes Agent
configured for CLI use plus its optional always-on gateway.

Other templates follow the same idea for other harnesses, such as Codex, Claude
Code, Gemini, Pi, or opencode.

### 2. Initial persistent config

`.env` plus `setup-host.sh` creates the first agent home. It does not run the
Hermes interactive wizard for you.

Hermes stores important user-level state under `/home/agent/.hermes/`: provider
auth, config, sessions, logs, memory, tool settings, hooks, skills, gateway
platform config, allowlists, cron/webhook state, cache, and other runtime
state. Treat this directory as private.

This persistence is the point of Hermes, not just an implementation detail.
Hermes is designed to improve through memory, session recall, and reusable
skills saved from experience. For normal Hermes use, keep one intentional
persistent home and let it accumulate useful context.

The TUI and the `gateway` daemon intentionally use the same persistent
`WORKSPACE_PATH` and `AGENT_HOME_PATH`. That gives the gateway the same Hermes
identity and configured workspace you tested interactively.

### 3. Persistent TUI run

Use this for normal interactive work:

```bash
docker compose run --rm agent
```

From the repo root:

```bash
just run hermes
```

This run stays active until you leave the TUI. It uses the persistent workspace
and persistent agent home from `.env`.

For an interactive shell instead of Hermes:

```bash
docker compose run --rm --entrypoint bash agent
```

### 4. Persistent daemon runs

Use this when you want the Hermes gateway to stay running in the background for
messaging, webhooks, and cron-like jobs:

```bash
docker compose --profile daemon up -d gateway
docker compose logs -f gateway
docker compose stop gateway
```

From the repo root:

```bash
just up hermes gateway
just logs hermes gateway
just ps hermes
just down hermes
```

The daemon runs:

```bash
hermes gateway run --replace --accept-hooks
```

In Docker, use `gateway run`, not `gateway start` or `gateway install`, because
`start/install` target systemd or launchd on the host. Hermes cron jobs are
created with `hermes cron ...`, but they fire from the running gateway's
background scheduler.

Run gateway setup only after the CLI works:

```bash
docker compose run --rm agent gateway setup
```

The gateway publishes the configured `HOST_PORT_*` preview ports because it is a
persistent remote endpoint. On a VPS, set `PORT_BIND_ADDRESS=0.0.0.0` only when
you intentionally want to expose those ports.

Use this when you want Hermes' browser dashboard for config, API keys, sessions,
and status:

```bash
docker compose --profile daemon up -d dashboard
docker compose logs -f dashboard
docker compose stop dashboard
```

From the repo root:

```bash
just up hermes dashboard
just logs hermes dashboard
just ps hermes
just down hermes
```

The dashboard runs:

```bash
hermes dashboard --host 0.0.0.0 --port 9119 --no-open --insecure --skip-build
```

Inside the container it must bind to `0.0.0.0` so Docker can publish it. The
host side still binds to `${PORT_BIND_ADDRESS}` and defaults to `127.0.0.1`.
Keep it that way unless you intentionally put the dashboard behind a real
firewall or reverse proxy. The dashboard can manage Hermes config and API keys,
so treat it as sensitive.

### 5. One-shot run with persistent home

Use this when sharing the same agent home is acceptable. For Hermes, this is the
normal one-shot mode because it preserves the same memory, skills, auth, and
tool configuration used by the TUI and gateway:

```bash
docker compose run --rm -T agent -z \
  "Summarize this project."
```

`hermes -z` is the programmatic one-shot entry point: pass the prompt as the
argument to `-z`, not through stdin. Hermes loads tools, memory, rules, and
`AGENTS.md` normally, but auto-bypasses approvals because this mode is intended
for scripts. This is simple, but the run can read and write the full persistent
`AGENT_HOME_PATH`: auth, config, sessions, logs, memory, skills, hooks, gateway
state, cron/webhook state, cache, and other runtime state.

Use this only when Docker is the sandbox boundary you want for the command:

```bash
docker compose run --rm -T agent -z \
  "Review this repo and suggest fixes."
```

You can also override the workspace for one command:

```bash
tmp_workspace=/srv/example-data/tmp/workspace-1
mkdir -p "$tmp_workspace"

docker compose run \
  -v "$tmp_workspace:/workspace" \
  --rm -T agent \
  -z \
  "Summarize this temporary workspace."
```

This still uses the persistent agent home from `.env`; only `/workspace` is
overridden for that command.

### 6. One-shot run with ephemeral home

This is not the main Hermes workflow. Hermes is strongest when the same
`.hermes` home persists across sessions so memory, skills, sessions, and gateway
state can compound over time.

Use an ephemeral home only for throwaway Docker/sandbox tests where you
intentionally do not want the run to teach or mutate your long-lived Hermes
identity. A useful temporary home usually still needs the tested `.hermes`
directory for auth and config. The stable minimal file set is not documented
narrowly enough for this template, so copy the whole directory only into runs
where you accept exposing that state.

```bash
template_dir=/srv/sannux/templates/hermes
tmp_workspace=/srv/example-data/tmp/workspace-1
persistent_home=/srv/example-data/agent-homes/hermes
tmp_home="$(mktemp -d)"
trap 'rm -rf "$tmp_home"' EXIT

mkdir -p "$tmp_workspace"
test -d "$persistent_home/.hermes"
cp -R "$persistent_home/.hermes" "$tmp_home/.hermes"
chmod -R go-rwx "$tmp_home"

docker compose --project-directory "$template_dir" run \
  -v "$tmp_workspace:/workspace" \
  -v "$tmp_home:/home/agent" \
  --rm -T agent \
  -z \
  "Summarize this temporary workspace."
```

Short warning: Docker `-v` can create missing host folders. Create and inspect
the folders yourself when the path matters.

Do not use an ephemeral copied home for normal Hermes work or for the 24/7
gateway. Any new memory, sessions, skills, gateway state, messaging auth,
allowlists, cron jobs, or webhook config written during that run disappear with
`tmp_home`.

## Preview ports

The regular `agent` service does not publish fixed host ports by default. If
Hermes starts an app inside a run, publish only the port you need on that
command:

```bash
docker compose run --rm -p 127.0.0.1:3001:3000 agent
```

That maps host port `3001` to container port `3000` for that one session. Make
the app inside the container listen on `0.0.0.0`.

The always-on gateway publishes the configured `HOST_PORT_*` values because it
is a persistent remote endpoint.

## Model routing with custom endpoints

Hermes can use a single OpenAI-compatible endpoint for the main model and still
override cheaper auxiliary tasks. For example:

```bash
docker compose run --rm agent model
```

Choose the custom endpoint provider, then use:

```txt
API base URL: https://models.example.com/v1
Model name: router:example-model-router
```

Or use a specific model slug instead of `router:...`. If you keep the key in
`.env`, name it `MODEL_ACCESS_KEY` and reference it from
`~/.hermes/config.yaml` for auxiliary tasks.

The important idea is not the specific endpoint vendor. It is that the expensive
main model, cheap compression/session-search model, MCP model, and fallback can
be chosen separately while the credentials stay inside this Hermes home.

Hermes does not currently expose custom request headers such as
`X-Model-Affinity` from the CLI. Do not add a proxy service here unless you have
a real cache-locality or cost problem to solve.

## Gateway safety checklist

Before leaving the gateway running on a VPS:

- Configure allowed users for each messaging platform in the Hermes env file
  under `${AGENT_HOME_PATH}/.hermes/.env`, for example
  `TELEGRAM_ALLOWED_USERS=123456789` or `GATEWAY_ALLOWED_USERS=123456789`.
- Keep Hermes approvals enabled. Use `approvals.mode: manual` or `smart`; do not
  turn them off for an always-on agent unless this is a throwaway lab.
- Start with the CLI first, then add gateways, cron jobs, MCP servers, and
  browser/voice tools one at a time.
- Keep the dashboard bound to localhost by default. If you expose it from a VPS,
  put a real firewall or reverse proxy in front before changing
  `PORT_BIND_ADDRESS` to `0.0.0.0`.
- Leave Hermes terminal commands on the container-local backend. Do not mount
  the host Docker socket just to make nested Docker work; that would punch
  through the main sandbox boundary.

## Recipes

From the repo root, with `just`:

```bash
just setup hermes
just config hermes
just build hermes
just rebuild hermes
just run hermes setup
just run hermes model
just run hermes
just up hermes gateway
just up hermes dashboard
just logs hermes gateway
just logs hermes dashboard
just down hermes
just shell hermes
```

From this template folder, without `just`:

```bash
./setup-host.sh
docker compose config --no-env-resolution
docker compose build
docker compose build --no-cache
docker compose run --rm agent setup
docker compose run --rm agent model
docker compose run --rm agent
docker compose --profile daemon up -d gateway
docker compose --profile daemon up -d dashboard
docker compose logs -f gateway
docker compose logs -f dashboard
docker compose stop gateway
docker compose stop dashboard
docker compose run --rm --entrypoint bash agent
docker compose down -v
```

## What's inside

Heads up: this image is significantly larger than the other templates because
Hermes is a Python codebase with a wide surface area, not a single npm CLI.

- Debian trixie-slim base pinned by digest.
- Hermes Agent installed via the official `install.sh` with code at
  `/usr/local/lib/hermes-agent` and command at `/usr/local/bin/hermes`.
- `uv` plus Python 3.11, managed by the Hermes installer.
- Hermes' curated `[all]` extra plus `[messaging]`, so the gateway has Telegram,
  Discord, and Slack adapter dependencies available at runtime.
- Built dashboard frontend at `/usr/local/lib/hermes-agent/hermes_cli/web_dist/`,
  so `hermes dashboard --skip-build` works in Docker.
- `ffmpeg`, `build-essential`, `python3-dev`, `libffi-dev` for Hermes voice,
  transcription, and native Python wheels.
- CLI helpers: `git`, `rg`, `fd`, `jq`, `fzf`, `bat`, `tree`, `less`.
- Non-root user `agent`, UID/GID matched to your host via build args.

If you do not need the voice/transcription stack, you can edit the Dockerfile to
drop `ffmpeg` and any extras you will not use. See the
[Hermes installer flags](https://github.com/NousResearch/hermes-agent/blob/main/scripts/install.sh)
for the available knobs.

## What's mounted

- `${WORKSPACE_PATH}` (host) -> `/workspace` (container): your project.
- `${AGENT_HOME_PATH}` (host) -> `/home/agent/` (container): `HERMES_HOME` lives
  here as `~/.hermes/`.

The Hermes code itself lives at `/usr/local/lib/hermes-agent` inside the image,
not in the bind mount, so the mount does not shadow the install. The container
is ephemeral (`--rm`); destroy and recreate it without losing state.

Both host paths are required and should live outside the `sannux` checkout. The
Compose file sets `create_host_path: false`, so missing directories fail early
instead of being silently created in the wrong place.

## What not to mount

Do not casually mount:

- your real home directory;
- SSH keys;
- cloud credentials;
- package manager tokens;
- global Git or GitHub config;
- the Docker socket.

Provider keys belong in this template's `.env` or in Hermes config/auth state
under `${AGENT_HOME_PATH}/.hermes`, scoped to this agent.

## What's not included

By design, this template is the sleep-tight baseline, not the paranoid maximum.
Out of the box:

- Network egress is open.
- The agent has default Linux capabilities.
- The root filesystem is not read-only.
- There is no GPU passthrough.

What you do get: the agent cannot reach your `~/.ssh/`, `~/.aws/`,
`~/.config/gh/`, `~/.npmrc`, or anything else outside the mounted workspace and
agent home unless you mount it yourself.

## Customize

Edit `Dockerfile` and `compose.yml` directly. Add tools you reach for, turn on
stricter security flags, pass `--gpus` for local model serving, or swap the base
image. After changing `Dockerfile`, run `just rebuild hermes` from the repo root
or `docker compose build --no-cache` from this template folder.

### Installing extra tools

Containers are disposable. If you install a package from an interactive shell,
that change is lost when the container is removed. For repeatable changes, edit
`Dockerfile` and rebuild the image.

Hermes can delegate work to many external tools when they exist in the
container, but this template intentionally does not preinstall every possible
agent CLI. Codex, Claude Code, Gemini, Pi, opencode, and similar harnesses each
bring their own install, auth, update, and security model. Add the ones you need
to `Dockerfile`, pin versions when the installer allows it, and verify each one
with a `--version` or smoke-test command during the build.

For example, keep optional delegate tools in an obvious local block:

```dockerfile
# Optional local extension point for tools Hermes may call.
# Replace these placeholders with the official install commands you trust.
RUN set -eux; \
    install-your-agent-cli-here; \
    your-agent-cli --version
```

If an agent CLI is Node-based, install Node in a normal runtime location before
installing that CLI. Do not rely on the private `/root/.hermes/node` copy used
to build Hermes' dashboard frontend; it is not part of the non-root agent user's
runtime contract.

For Debian packages, add them to the `apt-get install` list:

```dockerfile
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        your-package-here \
    && rm -rf /var/lib/apt/lists/*
```

For Hermes Python dependencies, install them into Hermes' managed venv during
the image build, not as the `agent` user at runtime:

```dockerfile
RUN cd /usr/local/lib/hermes-agent \
    && UV_PROJECT_ENVIRONMENT=/usr/local/lib/hermes-agent/venv \
        /root/.local/bin/uv sync --extra all --extra messaging --locked
```

If you need another upstream Hermes extra, add another `--extra name` there and
verify it with an import or command in the same `RUN` block. If you need an
arbitrary Python package that is not in Hermes' lockfile, pin it deliberately and
understand that it is outside Hermes' hash-locked dependency set.

Do not rely on `pip install` inside `docker compose run --rm --entrypoint bash
agent`: the Hermes venv is image-managed and root-owned on purpose.
