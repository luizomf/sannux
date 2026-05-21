# syntax=docker/dockerfile:1
#
# templates/remote-dev — generic SSH target for local apps with Remote SSH.
#
# Use this when the app stays on the host (Codex app, Antigravity, VS Code,
# etc.) but its commands and remote server should run inside a constrained
# Linux container.

FROM debian:trixie-slim@sha256:109e2c65005bf160609e4ba6acf7783752f8502ad218e298253428690b9eaa4b

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Baseline remote-development tools.
# openssh-server is the only service; the rest are common dependencies for
# Remote SSH app servers and coding tasks inside /workspace.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg \
        openssh-server \
        git git-lfs openssh-client \
        ripgrep fd-find jq fzf bat tree less \
        zip unzip xz-utils zstd file tar gzip \
        python3 python3-pip python3-venv pipx \
        build-essential pkg-config cmake ninja-build \
        bubblewrap \
        procps \
        vim nano \
    && ln -sf "$(which fdfind)" /usr/local/bin/fd \
    && ln -sf "$(which batcat)" /usr/local/bin/bat \
    && git lfs install --system \
    && chmod 1777 /tmp \
    && rm -rf /var/lib/apt/lists/*

# Node.js 22 LTS is useful for web projects and for remote app servers that
# expect a modern Node runtime on the SSH target.
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
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
