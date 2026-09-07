#!/usr/bin/env bash
# Offline image regression check; no Compose .env, credentials, or host mounts.
set -euo pipefail

if [[ $# -gt 1 || ${1:-} == -* ]]; then
    echo "Usage: $0 [image]" >&2
    exit 2
fi

image="${1:-sannux/pi:latest}"
docker run --rm --pull=never --network none --read-only \
    --tmpfs /home/agent:mode=1777 \
    --tmpfs /tmp:exec,mode=1777 \
    --workdir /tmp --entrypoint /bin/sh "$image" -ec '
        test "$(id -u)" -ne 0
        test "$(id -un)" = agent
        test "$HOME" = /home/agent
        test -z "$(ls -A "$HOME")"
        test "$(command -v uv)" = /usr/local/bin/uv
        test "$(command -v uvx)" = /usr/local/bin/uvx
        uv --version
        uvx --version
        uv --offline --no-config venv --python /usr/bin/python3 /tmp/uv-smoke
        VIRTUAL_ENV=/tmp/uv-smoke uv --offline --no-config run --no-project \
            --python /tmp/uv-smoke/bin/python python -c '\''
import os
import sys
assert os.getuid() != 0
assert sys.prefix == "/tmp/uv-smoke", sys.prefix
assert sys.prefix != sys.base_prefix
print("uv offline venv/run passed as non-root with an empty replacement home")
'\''
    '
