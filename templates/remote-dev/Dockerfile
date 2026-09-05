# syntax=docker/dockerfile:1
#
# templates/remote-dev — generic SSH target for local apps with Remote SSH.
#
# Use this when the app stays on the host (Codex app, Antigravity, VS Code,
# etc.) but its commands and remote server should run inside a constrained
# Linux container.

FROM debian:trixie-slim@sha256:d7e12182ce18b85b93007c1dedf31f2d29e01ccf3182cc4017c709b6259bc132

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends openssh-server \
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

# Node.js 22 LTS is useful for web projects and remote app servers. Pin npm
# separately because NodeSource can change it independently of the Node major.
ARG NPM_VERSION=12.0.2
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install --global "npm@${NPM_VERSION}" \
    && test "$(npm --version)" = "${NPM_VERSION}" \
    && npm cache clean --force \
    && rm -rf /var/lib/apt/lists/*

# Codex CLI itself. The npm package installs the `codex` binary on PATH.
# Under the hood it's a Rust core wrapped by an npm shim.
RUN npm install -g @openai/codex

ARG REMOTE_USER=agent
ARG USER_UID=1000
ARG USER_GID=1000
RUN set -eux; \
    case "${REMOTE_USER}" in \
        ""|root|*[!a-zA-Z0-9_-]*) \
            echo "Invalid REMOTE_USER: ${REMOTE_USER}" >&2; \
            exit 1; \
            ;; \
    esac; \
    case "${REMOTE_USER}" in \
        [0-9]*|-*) \
            echo "REMOTE_USER must not start with a digit or dash: ${REMOTE_USER}" >&2; \
            exit 1; \
            ;; \
    esac; \
    if getent passwd "${REMOTE_USER}" >/dev/null; then \
        echo "REMOTE_USER already exists: ${REMOTE_USER}" >&2; \
        exit 1; \
    fi; \
    if getent group "${USER_GID}" >/dev/null; then \
        AGENT_GROUP="$(getent group "${USER_GID}" | cut -d: -f1)"; \
    else \
        groupadd --gid "${USER_GID}" "${REMOTE_USER}"; \
        AGENT_GROUP="${REMOTE_USER}"; \
    fi; \
    useradd --uid "${USER_UID}" --gid "${AGENT_GROUP}" \
        --create-home --shell /bin/bash "${REMOTE_USER}"; \
    passwd -d "${REMOTE_USER}"

COPY sshd_config /etc/ssh/sshd_config
COPY sshd-entrypoint.sh /usr/local/bin/sannux-sshd
RUN chmod 0755 /usr/local/bin/sannux-sshd

USER ${REMOTE_USER}
WORKDIR /workspace
CMD ["bash"]
