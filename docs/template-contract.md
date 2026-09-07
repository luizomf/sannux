# Sannux Template Contract

This document is the canonical contract for sannux templates. It exists so a
new human or agent can compare a template against an explicit standard instead
of guessing from one example.

The contract checks structure and intent. It must not validate user-specific
values such as model names, endpoints, workspace paths, or local folder names.

## Core Concepts

- **Template**: a reusable environment definition under
  `templates/<template>/`. It defines how to run: Dockerfile, Compose service,
  tools, entrypoint, mounts, and resource limits.
- **Initial persistent config**: the first working agent home for a template. It
  usually comes from `.env` plus a setup script.
- **Run**: one concrete execution of a template with a workspace, an agent home,
  a command, logs, and an exit status.
- **Agent home**: the host directory mounted at `/home/agent` for a run. It
  stores runtime state such as auth, config, sessions, logs, cache, memory, and
  local history.
- **Persistent agent**: an agent identity that reuses the same agent home across
  runs.
- **Ephemeral run**: a run with a temporary agent home based on the template
  config. The caller may keep or delete that host folder after the command
  finishes.
- **Daemon service**: a long-lived Compose service with `up`, `logs`, `stop`,
  stable ports, and persistent state.

Use **Compose profile** when referring to Docker Compose `profiles:` so it does
not sound like a CLI config.

## Template Contract

Every template directory should remain self-contained enough to copy out of the
repo and run with plain Docker Compose.

Templates must keep these defaults unless the exception is documented:

- Use explicit `WORKSPACE_PATH` and `AGENT_HOME_PATH` values, or document a
  setup-script fallback that writes safe default paths outside the repo.
- Mount `WORKSPACE_PATH` at `/workspace`.
- Mount `AGENT_HOME_PATH` at `/home/agent`.
- Use `bind.create_host_path: false` for required host bind mounts declared in
  Compose.
- Keep `.env.example` safe: no secrets, no real credentials, and no
  user-specific host paths.
- Keep template docs in sync with root docs when user-facing behavior changes.

## Tool Update Policy

Only the Debian base image is pinned. Repository-controlled installed tools
follow upstream stable/latest distribution channels; Node.js follows current
LTS, not a numeric major. This includes RTK, npm, Codex and uv images. New tool
version, major, tag, commit or digest pins require explicit owner approval,
including proposed workarounds for compatibility regressions.

`just rebuild <template>` uses `docker compose build --no-cache --pull`:
installers resolve current releases again and external image stages refresh.
Normal cached builds may reuse older tools. Rebuilds do not restart containers
or update mounted extension snapshots, application state or home-installed
binaries that override the image's PATH.

Resolve a release once before fetching its artifact and matching upstream
checksum; fail on missing assets or checksum mismatch. Keep image-installed
executables usable by non-root users independently of the mounted home.
Use simple official installers rather than a custom update framework.

Inspect real CLI/API/schema and engine dependencies before changing selectors.
Keep meaningful capability tests instead of asserting a historical version.
Upstream-owned dependency locks, engine bounds, release-aging rules and managed
runtime constraints (such as Hermes' Python) are not sannux tool pins: consume
those with the current upstream source, without rewriting them. Protocol/schema
versions, Dockerfile syntax, model examples and UID/port values are not tool pins.
Debian packages track the repositories of the pinned Debian distribution, not
necessarily each project's newest release.

Floating tools favor fresh rebuilds over reproducibility: upstream changes or
outages can break a build or compatibility. Report concrete failures; do not
silently restore pins or weaken security/compatibility checks. See
[tool-update-compatibility.md](tool-update-compatibility.md) for the initial audit.

## Config Contract

The initial persistent config is allowed to contain CLI config and auth state for
the normal TUI run.

For one-shot ephemeral runs, mount only the files you accept exposing to that
run. For example, mounting `.codex` reuses the tested Codex config, but may also
expose API keys, auth state, memory, or other Codex data.

## Run Modes

Template docs must state which of these modes they support:

- **Persistent TUI run**: an interactive run that uses the `.env`
  `AGENT_HOME_PATH`.
- **One-shot persistent run**: a non-interactive command that uses the same
  persistent agent home. Template docs should warn when this is not the safest
  default for unattended YOLO-style automation.
- **One-shot ephemeral run**: a non-interactive command that creates a temporary
  agent home from template config and deletes it after the run.
- **Daemon service**: a long-lived Compose service, or an explicit statement
  that the template does not provide one.

Examples may use `docker compose run -v ...` for command-scoped mounts, but they
must preflight host paths first. The short `-v host:container` syntax bypasses
the `create_host_path: false` guard and Docker may create a missing host path.

## Exceptions

If a template does not fit this contract, stop and choose one path before
editing:

- Make a new template.
- Document a narrow exception in that template README.
- Update this global contract.

Do not silently drift a template away from the contract.

## Validation

Run this before finishing template or documentation changes:

```sh
just check
```

The check is structural. It verifies that contract files, required sections,
and core Compose invariants exist. It intentionally does not verify
user-specific values such as real paths, selected model names, provider URLs, or
local folder names.
