# syntax=docker/dockerfile:1
#
# templates/pi — Pi Coding Agent in a Debian-slim sandbox.
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
# Pin both architecture-specific release artifacts and verify them before install.
ARG RTK_VERSION=0.46.0
ARG RTK_AMD64_SHA256=79aa5b89c69566bbfeceb66c8a27cfbe52237fc7ee3e683115f43745a3262d21
ARG RTK_ARM64_SHA256=e8c2e1787f46017ea7c5a711b2bc6a7f7cf61c7ad69385b4c1e4daff1135dcd1
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
        amd64) \
            RTK_TARGET="x86_64-unknown-linux-musl"; \
            RTK_SHA256="${RTK_AMD64_SHA256}"; \
            ;; \
        arm64) \
            RTK_TARGET="aarch64-unknown-linux-gnu"; \
            RTK_SHA256="${RTK_ARM64_SHA256}"; \
            ;; \
        *) \
            echo "Unsupported RTK architecture: $(dpkg --print-architecture)" >&2; \
            exit 1; \
            ;; \
    esac; \
    RTK_ARCHIVE="/tmp/rtk.tar.gz"; \
    curl -fsSL \
        "https://github.com/rtk-ai/rtk/releases/download/v${RTK_VERSION}/rtk-${RTK_TARGET}.tar.gz" \
        -o "${RTK_ARCHIVE}"; \
    printf '%s  %s\n' "${RTK_SHA256}" "${RTK_ARCHIVE}" | sha256sum -c -; \
    tar -xzf "${RTK_ARCHIVE}" -C /usr/local/bin rtk; \
    rm -f "${RTK_ARCHIVE}"; \
    test "$(rtk --version)" = "rtk ${RTK_VERSION}"

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

COPY browser-fetch/browser-fetch.mjs /opt/sannux/browser-fetch/browser-fetch.mjs

RUN chmod 0755 /opt/sannux/browser-fetch/browser-fetch.mjs \
    && ln -sf /opt/sannux/browser-fetch/browser-fetch.mjs /usr/local/bin/browser-fetch

# Pi Coding Agent. The npm package installs the `pi` binary on PATH.
RUN npm install -g @earendil-works/pi-coding-agent

# Codex is available for Pi extensions and nested agent calls.
RUN npm install -g "@openai/codex"

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

# Keep uv/uvx outside the mounted agent home, available to every fresh run.
COPY --from=ghcr.io/astral-sh/uv:0.11.11@sha256:798712e57f879c5393777cbda2bb309b29fcdeb0532129d4b1c3125c5385975a /uv /uvx /usr/local/bin/

# Image entrypoint. With ENTRYPOINT (instead of CMD), any args passed to
# `docker compose run --rm agent <args>` go straight to `pi`. So:
#   docker compose run --rm agent             -> pi
#   docker compose run --rm agent --version   -> pi --version
#   docker compose run --rm agent -p "..."    -> pi -p "..." (print mode)
# For an interactive shell, override the entrypoint:
#   docker compose run --rm --entrypoint bash agent
ENTRYPOINT ["pi"]
