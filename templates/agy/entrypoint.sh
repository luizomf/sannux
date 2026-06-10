#!/usr/bin/env bash

set -e
set -Eou pipefail

export PATH="$HOME/.local/bin:$PATH"

if ! command -v agy >/dev/null 2>&1
then
  curl -fsSL https://antigravity.google/cli/install.sh | bash
fi

exec agy "$@"
