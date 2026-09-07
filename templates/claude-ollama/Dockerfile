# syntax=docker/dockerfile:1
#
# templates/claude-ollama — Claude Code + Ollama in a Debian-slim sandbox.
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

FROM debian:trixie-slim@sha256:d7e12182ce18b85b93007c1dedf31f2d29e01ccf3182cc4017c709b6259bc132

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg tmux gnupg \
        build-essential git git-lfs openssh-client \
        ripgrep fd-find jq fzf bat tree less tar gzip \
        inetutils-traceroute inetutils-ping iproute2 \
        zip unzip xz-utils zstd file lsof make psmisc \
        python3 python3-pip python3-dev python3-venv pipx \
        build-essential pkg-config cmake ninja-build \
        procps vim nano gh ffmpeg imagemagick pandoc \
        fontconfig fonts-dejavu-core fonts-noto-color-emoji \
        chromium bubblewrap rsync socat bc \
    && ln -sf "$(which fdfind)" /usr/local/bin/fd \
    && ln -sf "$(which batcat)" /usr/local/bin/bat \
    && git lfs install --system \
    && rm -rf /var/lib/apt/lists/*

# RTK compresses verbose development-command output before it reaches an agent.
# Resolve latest once, then verify the matching upstream release checksum.
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
        amd64) \
            RTK_TARGET="x86_64-unknown-linux-musl"; \
            ;; \
        arm64) \
            RTK_TARGET="aarch64-unknown-linux-gnu"; \
            ;; \
        *) \
            echo "Unsupported RTK architecture: $(dpkg --print-architecture)" >&2; \
            exit 1; \
            ;; \
    esac; \
    curl -fsSL https://api.github.com/repos/rtk-ai/rtk/releases/latest -o /tmp/rtk-release.json; \
    RTK_TAG="$(jq -er '.tag_name | select(test("^v[0-9]+[.][0-9]+[.][0-9]+$"))' /tmp/rtk-release.json)"; \
    RTK_ARCHIVE="rtk-${RTK_TARGET}.tar.gz"; \
    RTK_URL="https://github.com/rtk-ai/rtk/releases/download/${RTK_TAG}"; \
    cd /tmp; \
    curl -fsSL "${RTK_URL}/${RTK_ARCHIVE}" -o "${RTK_ARCHIVE}"; \
    curl -fsSL "${RTK_URL}/checksums.txt" -o rtk-checksums.txt; \
    awk -v archive="${RTK_ARCHIVE}" '$2 == archive {print; found++} END {if (found != 1) exit 1}' \
        rtk-checksums.txt > rtk-checksum.txt; \
    sha256sum -c - < rtk-checksum.txt; \
    tar -xzf "${RTK_ARCHIVE}" -C /usr/local/bin rtk; \
    rm -f "${RTK_ARCHIVE}" rtk-release.json rtk-checksums.txt rtk-checksum.txt; \
    test "$(rtk --version)" = "rtk ${RTK_TAG#v}"

# Follow NodeSource's current LTS channel and npm's latest release.
# Fail rather than silently install npm on an unsupported Node engine.
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x -o /tmp/nodesource.sh \
    && bash /tmp/nodesource.sh \
    && rm /tmp/nodesource.sh \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install --global --engine-strict npm@latest \
    && node --version && npm --version \
    && npm cache clean --force \
    && rm -rf /var/lib/apt/lists/*

# Claude Code itself. The npm package installs the `claude` binary on PATH.
# This template points Claude Code at an Anthropic-compatible Ollama endpoint
# through environment variables in compose.yml / .env.
RUN npm install -g @anthropic-ai/claude-code

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
# `docker compose run --rm agent <args>` go straight to `claude`. So:
#   docker compose run --rm agent             -> claude
#   docker compose run --rm agent --version   -> claude --version
# For an interactive shell, override the entrypoint:
#   docker compose run --rm --entrypoint bash agent
ENTRYPOINT ["claude"]
