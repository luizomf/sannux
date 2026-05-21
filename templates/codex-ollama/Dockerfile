# syntax=docker/dockerfile:1
#
# templates/codex-ollama — Codex CLI + Ollama in a Debian-slim sandbox.
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

# ADDED MORE UTILS BECAUSE CODEX REQUESTED IT.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg \
        git git-lfs openssh-client \
        ripgrep fd-find jq fzf bat tree less \
        zip unzip xz-utils zstd file \
        python3 python3-pip python3-venv pipx \
        build-essential pkg-config cmake ninja-build \
        procps \
        vim nano \
        ffmpeg imagemagick pandoc \
        fontconfig fonts-dejavu-core fonts-noto-color-emoji \
        chromium \
        bubblewrap \
    && ln -sf "$(which fdfind)" /usr/local/bin/fd \
    && ln -sf "$(which batcat)" /usr/local/bin/bat \
    && git lfs install --system \
    && rm -rf /var/lib/apt/lists/*

# Node.js 22 LTS via NodeSource. Codex CLI ships as an npm package; pinning
# to LTS gives ~30 months of support and keeps `npm install -g` predictable.
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Codex CLI itself. The npm package installs the `codex` binary on PATH.
# Under the hood it's a Rust core wrapped by an npm shim. This template uses
# Codex as the agent harness. setup-host.sh writes the persisted
# /home/agent/.codex/config.toml that points Codex at an Ollama
# OpenAI-compatible endpoint
RUN npm install -g @openai/codex

# Non-root user. UID/GID come as build args and default to 1000:1000.
ARG USER_UID=1000
ARG USER_GID=1000
# This intentionally fails if USER_GID already exists in the base image.
RUN groupadd --gid ${USER_GID} agent \
 && useradd --uid ${USER_UID} --gid ${USER_GID} -m -s /bin/bash agent

USER agent
WORKDIR /workspace

# Image entrypoint. With ENTRYPOINT (instead of CMD), any args passed to
# `docker compose run --rm agent <args>` go straight to `codex`. So:
#   docker compose run --rm agent             -> codex
#   docker compose run --rm agent --version   -> codex --version
#   docker compose run --rm agent exec "..."  -> codex exec "..." (headless)
# For an interactive shell, override the entrypoint:
#   docker compose run --rm --entrypoint bash agent
ENTRYPOINT ["codex"]
