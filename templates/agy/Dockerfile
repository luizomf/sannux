# syntax=docker/dockerfile:1
#
# templates/agy — Antigravity CLI (agy) in a Debian-slim sandbox.
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
        git git-lfs openssh-client \
        ripgrep fd-find jq fzf bat tree less \
        zip unzip xz-utils zstd file \
        python3 python3-pip python3-venv pipx \
        build-essential pkg-config cmake ninja-build \
        procps \
        vim nano gh \
        ffmpeg imagemagick pandoc \
        fontconfig fonts-dejavu-core fonts-noto-color-emoji \
        chromium \
        bubblewrap \
    && ln -sf "$(which fdfind)" /usr/local/bin/fd \
    && ln -sf "$(which batcat)" /usr/local/bin/bat \
    && git lfs install --system \
    && rm -rf /var/lib/apt/lists/*

# Node.js 24 LTS via NodeSource. Pin npm separately because NodeSource can
# change the bundled npm version independently of the selected Node.js major.
ARG NPM_VERSION=12.0.2
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install --global "npm@${NPM_VERSION}" \
    && test "$(npm --version)" = "${NPM_VERSION}" \
    && npm cache clean --force \
    && rm -rf /var/lib/apt/lists/*

# Small browser-backed fetcher for local models. It uses the Debian Chromium
# package already installed above and keeps a fresh browser profile per run.
RUN mkdir -p /opt/sannux/browser-fetch \
    && npm install --prefix /opt/sannux/browser-fetch --omit=dev --ignore-scripts playwright-core \
    && npm cache clean --force

# Non-root user. UID/GID come as build args and default to 1000:1000.
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

COPY --chmod=u=rwx,go=rx entrypoint.sh /entrypoint.sh

USER agent
WORKDIR /workspace

# Image entrypoint. With ENTRYPOINT (instead of CMD), any args passed to
# `docker compose run --rm agent <args>` go straight to `agy`. So:
#   docker compose run --rm agent             -> agy
#   docker compose run --rm agent --version   -> agy --version
# For an interactive shell, override the entrypoint:
#   docker compose run --rm --entrypoint bash agent
ENTRYPOINT ["/entrypoint.sh"]
