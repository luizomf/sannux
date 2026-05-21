# syntax=docker/dockerfile:1
#
# templates/opencode — opencode (SST) in a Debian-slim sandbox.
#
# Why debian:trixie-slim pinned by digest:
#   glibc compatibility for every prebuilt binary the agent might pull in
#   (Node native addons, Python wheels, Bun, Rust binaries). Alpine + musl
#   would be smaller but breaks too many native deps for an "it just works"
#   template.
#
# Why a non-root user with build-arg UID/GID:
#   Files written to bind-mounted volumes inherit the in-container user's
#   UID. Aligning it to the host user keeps those files editable without
#   sudo. On macOS this is largely cosmetic (Docker Desktop translates),
#   on Linux it matters.

FROM debian:trixie-slim@sha256:109e2c65005bf160609e4ba6acf7783752f8502ad218e298253428690b9eaa4b

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Baseline tools the agent reaches for.
#   - ca-certificates / curl / wget / gnupg: HTTPS, signing, downloads.
#   - git: agents read and write code, often through git.
#   - ripgrep / fd-find / jq / fzf / bat / tree / less: search and inspect.
#   - python3 + pip + venv + pipx: Python is the second language agents try.
#   - build-essential: native deps for `npm install` / `pip install`.
#   - procps: `ps`, useful when agents debug processes.
#
# fd-find ships as `fdfind` and bat as `batcat` on Debian (name conflicts
# with other packages); the symlinks below restore the canonical names.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg \
        git \
        ripgrep fd-find jq fzf bat tree less \
        python3 python3-pip python3-venv pipx \
        build-essential \
        procps \
    && ln -sf "$(which fdfind)" /usr/local/bin/fd \
    && ln -sf "$(which batcat)" /usr/local/bin/bat \
    && rm -rf /var/lib/apt/lists/*

# Node.js 22 LTS via NodeSource. opencode ships as an npm package; pinning
# to LTS gives ~30 months of support and keeps `npm install -g` predictable.
# (SST also offers a curl-bash installer that drops a self-contained binary
# into ~/.opencode/bin — we use npm here for parity with the other
# templates and to keep the install transparent.)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# opencode itself. The npm package installs the `opencode` binary on PATH.
RUN npm install -g opencode-ai@latest

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

USER agent
WORKDIR /workspace

# Image entrypoint. With ENTRYPOINT (instead of CMD), any args passed to
# `docker compose run --rm agent <args>` go straight to `opencode`. So:
#   docker compose run --rm agent                -> opencode
#   docker compose run --rm agent --version      -> opencode --version
#   docker compose run --rm agent auth login     -> provider login picker
# For an interactive shell, override the entrypoint:
#   docker compose run --rm --entrypoint bash agent
ENTRYPOINT ["opencode"]
