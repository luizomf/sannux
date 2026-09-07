#!/usr/bin/env bash

set -e
set -Eou pipefail

export PATH="$HOME/.local/bin:$PATH"

# The image supplies agy; explicit home-installed overrides remain supported.
exec agy "$@"
