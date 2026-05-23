# sannux — top-level recipes.
#
# Thin wrapper over `docker compose` inside `templates/<name>/`. Convenience
# for users who clone the whole repo. Each template folder also works on its
# own with plain `docker compose ...` — no dependency on this justfile.

compose_env := "env -u AGENT_HOME_PATH -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN -u ANTHROPIC_BASE_URL -u ANTHROPIC_MODEL -u CODEX_APPROVAL_POLICY -u CODEX_MODEL -u CODEX_MODEL_CATALOG_HOST_PATH -u CODEX_MODEL_CATALOG_PATH -u CODEX_MODEL_PROVIDER -u CODEX_MODEL_PROVIDER_NAME -u CODEX_MODEL_REASONING_EFFORT -u CODEX_PERSONALITY -u CODEX_PROFILE -u CODEX_SANDBOX_MODE -u COLORTERM -u CPU_LIMIT -u FORCE_COLOR -u HOST_PORT_3000 -u HOST_PORT_8000 -u HOST_PORT_8080 -u HOST_PORT_DASHBOARD -u HOST_SSH_PORT -u MEM_LIMIT -u OLLAMA_BASE_URL -u PI_CODING_AGENT_DIR -u PORT_BIND_ADDRESS -u REMOTE_USER -u SANNUX_COLORTERM -u SANNUX_FORCE_COLOR -u SANNUX_TERM -u SSH_BIND_ADDRESS -u SSH_HOST_ALIAS -u TERM -u USER_GID -u USER_UID -u WORKSPACE_PATH"

# Default: list available recipes
default:
  @just --list

_require-template template:
  #!/usr/bin/env bash
  if [[ ! -d "templates/{{template}}" ]]; then
    echo "Unknown template: {{template}}"
    echo "Run: just templates"
    exit 1
  fi

_require-env template:
  #!/usr/bin/env bash
  just _require-template {{template}}
  template_name="{{template}}"
  env_file="templates/${template_name}/.env"
  if [[ ! -f "${env_file}" ]]; then
    echo "Missing ${env_file}"
    echo "Run: just init {{template}}"
    exit 1
  fi

_require-host-paths template:
  #!/usr/bin/env bash
  set -euo pipefail
  just _require-env {{template}}
  template_name="{{template}}"
  env_file="templates/${template_name}/.env"

  get_env_value() {
    local key="$1"
    awk -F= -v key="${key}" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "${env_file}"
  }

  check_host_dir() {
    local key="$1"
    local value="$2"
    if [[ -z "${value}" ]]; then
      echo "${key} is empty in ${env_file}"
      echo "Run: just setup ${template_name}, or edit ${env_file}"
      exit 1
    fi
    if [[ "${value}" != /* ]]; then
      echo "${key} must be an absolute host path in ${env_file}: ${value}"
      exit 1
    fi
    if [[ ! -d "${value}" ]]; then
      echo "${key} does not exist: ${value}"
      echo "Run: just setup ${template_name}, or create the directory"
      exit 1
    fi
  }

  check_host_dir WORKSPACE_PATH "$(get_env_value WORKSPACE_PATH)"
  check_host_dir AGENT_HOME_PATH "$(get_env_value AGENT_HOME_PATH)"

# List templates currently available
templates:
  @ls -1 templates 2>/dev/null || echo "(no templates yet — see open issues)"

# Run repository contract checks
check:
  @python3 scripts/check-doc-contract.py

# Create a template .env from .env.example without overwriting an existing one
init template:
  #!/usr/bin/env bash
  set -euo pipefail
  just _require-template {{template}}
  env_file="templates/{{template}}/.env"
  example_file="templates/{{template}}/.env.example"
  if [[ -f "${env_file}" ]]; then
    echo "${env_file} already exists"
    exit 0
  fi
  install -m 0600 "${example_file}" "${env_file}"
  echo "Created ${env_file}"
  echo "Edit WORKSPACE_PATH and AGENT_HOME_PATH, or run: just setup {{template}}"

# Run a template-specific host setup script when available
setup template:
  #!/usr/bin/env bash
  set -euo pipefail
  just _require-template {{template}}
  script="templates/{{template}}/setup-host.sh"
  if [[ ! -x "${script}" ]]; then
    echo "No setup script for template: {{template}}"
    exit 1
  fi
  "${script}"

# Render and validate the Compose config for a template
config template:
  @just _require-env {{template}}
  @cd templates/{{template}} && {{compose_env}} docker compose config --no-env-resolution

# Run a template-specific docker compose (just a wrapper to avoid cd)
compose template *compose_args:
  @just _require-host-paths {{template}}
  @cd templates/{{template}} && {{compose_env}} docker compose {{compose_args}}

# Build the image for a template (e.g. `just build claude-code`)
build template:
  @just _require-env {{template}}
  @cd templates/{{template}} && {{compose_env}} docker compose build

# Build with no cache
rebuild template:
  @just _require-env {{template}}
  @cd templates/{{template}} && {{compose_env}} docker compose build --no-cache

# Run the agent in an ephemeral container
run template *args:
  @just _require-host-paths {{template}}
  @cd templates/{{template}} && {{compose_env}} docker compose run --rm agent {{args}}

# Start long-running Compose profile services in the background
up template *services:
  @test -n "{{services}}" || { echo "Usage: just up {{template}} <service...>" >&2; exit 2; }
  @just _require-host-paths {{template}}
  @cd templates/{{template}} && {{compose_env}} docker compose --profile daemon up -d {{services}}

# Follow logs for a long-running service
logs template service:
  @just _require-env {{template}}
  @cd templates/{{template}} && {{compose_env}} docker compose logs -f {{service}}

# Show containers for a template
ps template *args:
  @just _require-env {{template}}
  @cd templates/{{template}} && {{compose_env}} docker compose ps

# Stop a long-running service without deleting persisted state
stop template *services:
  @test -n "{{services}}" || { echo "Usage: just stop {{template}} <service...>" >&2; exit 2; }
  @just _require-env {{template}}
  @cd templates/{{template}} && {{compose_env}} docker compose stop {{services}}

# Open an interactive bash shell inside the container
shell template:
  @just _require-host-paths {{template}}
  @cd templates/{{template}} && {{compose_env}} docker compose run --rm --entrypoint bash agent

# Open an interactive root bash shell for debugging only
root-shell template:
  @just _require-host-paths {{template}}
  @cd templates/{{template}} && {{compose_env}} docker compose run --rm --user root --entrypoint bash agent

# Stop containers and remove their named volumes
down template:
  @just _require-env {{template}}
  @cd templates/{{template}} && {{compose_env}} docker compose --profile '*' down -v
