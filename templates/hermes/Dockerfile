# syntax=docker/dockerfile:1
#
# templates/hermes — Hermes Agent (NousResearch) in a Debian-slim sandbox.
#
# Why debian:trixie-slim pinned by digest:
#   glibc compatibility for every prebuilt binary the agent might pull in
#   (Node native addons, Python wheels, Rust binaries). Alpine + musl
#   would be smaller but breaks too many native deps for an "it just works"
#   template.
#
# Why a non-root user with build-arg UID/GID:
#   Files written to bind-mounted volumes inherit the in-container user's
#   UID. Aligning it to the host user keeps those files editable without
#   sudo. On macOS this is largely cosmetic (Docker Desktop translates),
#   on Linux it matters.
#
# Why this image is heavier than the other templates:
#   Hermes is not a single npm package — it's a Python codebase with
#   sizeable optional extras (browser automation, voice, transcription,
#   messaging gateways). Expect a multi-gigabyte image. If you need a leaner
#   build, edit the install command below to skip extras you don't use.

FROM debian:trixie-slim@sha256:109e2c65005bf160609e4ba6acf7783752f8502ad218e298253428690b9eaa4b

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_PYTHON_INSTALL_DIR=/usr/local/share/uv/python

# Baseline tools the agent reaches for, plus what Hermes' install.sh needs:
#   - ca-certificates / curl / wget / gnupg: HTTPS, downloads, install.sh.
#   - git: install.sh clones the Hermes repo; agents read/write code via git.
#   - passwd: groupadd/useradd for the non-root agent user.
#   - build-essential + python3-dev + libffi-dev: native deps for the [all]
#     extras (some wheels compile from source on first install).
#   - ffmpeg: required by Hermes' voice/transcription extras at runtime.
#   - ripgrep / fd-find / jq / fzf / bat / tree / less: search and inspect.
#   - python3 + python3-venv: uv (installed by install.sh) re-downloads
#     Hermes' target Python into /usr/local/share/uv/python, but the system
#     one is a fallback if uv ever fails.
#   - procps: `ps`, useful when agents debug processes.
#
# fd-find ships as `fdfind` and bat as `batcat` on Debian (name conflicts
# with other packages); the symlinks below restore the canonical names.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg \
        git \
        passwd \
        build-essential python3-dev libffi-dev \
        ffmpeg \
        ripgrep fd-find jq fzf bat tree less \
        python3 python3-venv \
        procps \
    && ln -sf "$(which fdfind)" /usr/local/bin/fd \
    && ln -sf "$(which batcat)" /usr/local/bin/bat \
    && rm -rf /var/lib/apt/lists/*

# Hermes install. Run as root so the installer auto-detects the FHS layout
# and drops the code in /usr/local/lib/hermes-agent + the binary symlink
# in /usr/local/bin/hermes. That keeps the install OUT of any directory we
# later bind-mount over /home/agent at runtime.
#
# Flags:
#   --skip-setup  defers the interactive `hermes setup` wizard to first
#                 run inside the container (where it can prompt the user
#                 and write to the persisted AGENT_HOME_PATH mount).
#
# The installer takes care of uv + Python 3.11 + the curated [all] extras.
# Upstream [all] intentionally excludes messaging adapters, so this template
# adds [messaging] explicitly because gateway is a first-class service here.
# The web dashboard also needs its React/Vite frontend built into
# hermes_cli/web_dist so dashboard runs can use --skip-build in containers.
# Expect this layer to take a while and to produce most of the image's size.
RUN set -eux; \
    git clone --depth 1 --branch main \
        https://github.com/NousResearch/hermes-agent.git \
        /tmp/hermes-agent-src; \
    bash /tmp/hermes-agent-src/scripts/install.sh --skip-setup; \
    rm -rf /tmp/hermes-agent-src; \
    cd /usr/local/lib/hermes-agent; \
    UV_PROJECT_ENVIRONMENT=/usr/local/lib/hermes-agent/venv \
        /root/.local/bin/uv sync --extra all --extra messaging --locked; \
    export PATH="/root/.hermes/node/bin:${PATH}"; \
    cd /usr/local/lib/hermes-agent/web; \
    npm ci --no-audit --no-fund; \
    npm run build; \
    rm -rf node_modules /root/.npm; \
    test -x /usr/local/bin/hermes; \
    test -x /usr/local/lib/hermes-agent/venv/bin/hermes; \
    /usr/local/lib/hermes-agent/venv/bin/python -c 'import telegram'; \
    test -f /usr/local/lib/hermes-agent/hermes_cli/web_dist/index.html

# Make Hermes' managed Python visible to the non-root agent user. The venv stays
# owned by root; users should rebuild the image for dependency changes.
ENV PATH=/usr/local/lib/hermes-agent/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/games:/usr/games
RUN printf '%s\n' \
        '#!/usr/bin/env sh' \
        'exec /usr/local/lib/hermes-agent/venv/bin/python "$@"' \
        > /usr/local/bin/python \
    && chmod 0755 /usr/local/bin/python

# Optional local extension point:
# Add delegate CLIs that Hermes should call from inside the container here
# (Codex, Claude Code, Gemini, Pi, opencode, or private tools). Keep installs
# in the image, pin versions when possible, and verify each CLI with a
# `--version` or smoke-test command during the build instead of relying on
# interactive runtime installs.

# Non-root user. UID/GID come as build args and default to 1000:1000. Some
# host GIDs, such as macOS `20`, already exist in Debian, so reuse existing
# groups instead of failing the build.
ARG USER_UID=1000
ARG USER_GID=1000
RUN set -eux; \
    if getent group "${USER_GID}" >/dev/null; then \
        AGENT_GROUP="$(getent group "${USER_GID}" | cut -d: -f1)"; \
    else \
        groupadd --gid "${USER_GID}" agent; \
        AGENT_GROUP=agent; \
    fi; \
    useradd --uid "${USER_UID}" --gid "${AGENT_GROUP}" \
        --create-home --shell /bin/bash agent

# Move HERMES_HOME (auth, config, sessions, logs) into the agent's home
# directory so it lands inside the AGENT_HOME_PATH bind mount at runtime. Without
# this, Hermes would default to /root/.hermes — which we cannot reach as
# the agent user.
ENV HERMES_HOME=/home/agent/.hermes

USER agent
WORKDIR /workspace

# Image entrypoint. With ENTRYPOINT (instead of CMD), any args passed to
# `docker compose run --rm agent <args>` go straight to `hermes`. So:
#   docker compose run --rm agent             -> hermes
#   docker compose run --rm agent --version   -> hermes --version
#   docker compose run --rm agent setup       -> hermes setup (first-run wizard)
# For an interactive shell, override the entrypoint:
#   docker compose run --rm --entrypoint bash agent
ENTRYPOINT ["hermes"]
