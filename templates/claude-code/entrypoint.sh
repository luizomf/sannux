#!/usr/bin/env bash

set -e
set -Eou pipefail

export PATH="$HOME/.local/bin:$PATH"

if ! command -v claude >/dev/null 2>&1
then
  mkdir -p ~/.local/
  mv -n /claude-install/.local/* ~/.local/
  cd "$HOME"/.local/share/claude/versions/ || exit 1
  bash -lc "./$(ls -t1 | head -n 1) install"
fi

claude
