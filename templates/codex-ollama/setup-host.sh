#!/usr/bin/env bash
set -euo pipefail

template_name=codex-ollama
template_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root_candidate="$(cd "${template_dir}/../.." && pwd)"
repo_root=""
if [[ -d "${repo_root_candidate}/.git" ]]; then
  repo_root="${repo_root_candidate}"
elif [[ -d "${repo_root_candidate}/templates" && -f "${repo_root_candidate}/AGENTS.md" ]]; then
  repo_root="${repo_root_candidate}"
fi
env_file="${template_dir}/.env"
example_file="${template_dir}/.env.example"
config_template="${template_dir}/codex-config.toml.template"

fail() {
  echo "Error: $*" >&2
  exit 1
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

get_env_value() {
  local key="$1"
  awk -F= -v key="${key}" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "${env_file}"
}

set_env_value() {
  local key="$1"
  local value="$2"
  local tmp
  tmp="$(mktemp)"
  awk -v key="${key}" -v value="${value}" '
    BEGIN { done = 0 }
    $0 ~ "^" key "=" {
      print key "=" value
      done = 1
      next
    }
    { print }
    END {
      if (!done) {
        print key "=" value
      }
    }
  ' "${env_file}" > "${tmp}"
  mv "${tmp}" "${env_file}"
}

require_absolute_path() {
  local key="$1"
  local value="$2"
  case "${value}" in
    /*) ;;
    *) fail "${key} must be an absolute host path: ${value}" ;;
  esac
}

reject_unsafe_path() {
  local key="$1"
  local value="$2"
  case "${value}" in
    /|"${HOME}"|"${template_dir}"|"${template_dir}/"*)
      fail "${key} must point to a dedicated directory outside your real home root and outside this template directory: ${value}"
      ;;
  esac

  if [[ -n "${repo_root}" ]]; then
    case "${value}" in
      "${repo_root}"|"${repo_root}/"*)
        fail "${key} must point to a dedicated directory outside the sannux checkout: ${value}"
        ;;
    esac
  fi
}

require_choice() {
  local key="$1"
  local value="$2"
  shift 2
  local allowed
  for allowed in "$@"; do
    [[ "${value}" == "${allowed}" ]] && return 0
  done
  fail "${key} must be one of: $*"
}

toml_string() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  printf '"%s"' "${value}"
}

render_config() {
  local output_file="$1"
  local codex_model_toml="$2"
  local codex_model_provider_toml="$3"
  local codex_model_provider_name_toml="$4"
  local codex_profile_toml="$5"
  local codex_personality_toml="$6"
  local codex_reasoning_toml="$7"
  local ollama_base_url_toml="$8"
  local catalog_path_toml="$9"
  local approval_policy_toml="${10}"
  local sandbox_mode_toml="${11}"
  local line

  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line//__CODEX_MODEL__/${codex_model_toml}}"
    line="${line//__CODEX_MODEL_PROVIDER__/${codex_model_provider_toml}}"
    line="${line//__CODEX_MODEL_PROVIDER_NAME__/${codex_model_provider_name_toml}}"
    line="${line//__CODEX_MODEL_PROVIDER_KEY__/${codex_model_provider_toml}}"
    line="${line//__CODEX_PROFILE_KEY__/${codex_profile_toml}}"
    line="${line//__CODEX_PERSONALITY__/${codex_personality_toml}}"
    line="${line//__CODEX_MODEL_REASONING_EFFORT__/${codex_reasoning_toml}}"
    line="${line//__OLLAMA_BASE_URL__/${ollama_base_url_toml}}"
    line="${line//__CODEX_MODEL_CATALOG_PATH__/${catalog_path_toml}}"
    line="${line//__CODEX_APPROVAL_POLICY__/${approval_policy_toml}}"
    line="${line//__CODEX_SANDBOX_MODE__/${sandbox_mode_toml}}"
    printf '%s\n' "${line}"
  done < "${config_template}" > "${output_file}"
}

need_command awk
need_command cmp
need_command install

if [[ ! -f "${env_file}" ]]; then
  install -m 0600 "${example_file}" "${env_file}"
  echo "Created ${env_file}"
fi

default_base="${HOME}/sannux-data"
user_uid="$(get_env_value USER_UID)"
user_gid="$(get_env_value USER_GID)"
workspace_path="$(get_env_value WORKSPACE_PATH)"
agent_home_path="$(get_env_value AGENT_HOME_PATH)"
ollama_base_url="$(get_env_value OLLAMA_BASE_URL)"
codex_model="$(get_env_value CODEX_MODEL)"
codex_model_provider="$(get_env_value CODEX_MODEL_PROVIDER)"
codex_model_provider_name="$(get_env_value CODEX_MODEL_PROVIDER_NAME)"
codex_profile="$(get_env_value CODEX_PROFILE)"
codex_personality="$(get_env_value CODEX_PERSONALITY)"
codex_reasoning="$(get_env_value CODEX_MODEL_REASONING_EFFORT)"
codex_catalog_path="$(get_env_value CODEX_MODEL_CATALOG_PATH)"
codex_approval_policy="$(get_env_value CODEX_APPROVAL_POLICY)"
codex_sandbox_mode="$(get_env_value CODEX_SANDBOX_MODE)"

user_uid="${user_uid:-$(id -u)}"
user_gid="${user_gid:-$(id -g)}"
workspace_path="${workspace_path:-${default_base}/workspaces/${template_name}}"
agent_home_path="${agent_home_path:-${default_base}/agent-homes/${template_name}}"
ollama_base_url="${ollama_base_url:-http://host.docker.internal:11434/v1}"
codex_model="${codex_model:-local-model:8b}"
codex_model_provider="${codex_model_provider:-ollama_lan}"
codex_model_provider_name="${codex_model_provider_name:-Ollama}"
codex_profile="${codex_profile:-local-model-8b}"
codex_personality="${codex_personality:-friendly}"
codex_reasoning="${codex_reasoning:-high}"
codex_catalog_path="${codex_catalog_path:-/opt/sannux/model_catalog.json}"
codex_approval_policy="${codex_approval_policy:-never}"
codex_sandbox_mode="${codex_sandbox_mode:-danger-full-access}"

require_absolute_path WORKSPACE_PATH "${workspace_path}"
require_absolute_path AGENT_HOME_PATH "${agent_home_path}"
reject_unsafe_path WORKSPACE_PATH "${workspace_path}"
reject_unsafe_path AGENT_HOME_PATH "${agent_home_path}"
require_choice CODEX_MODEL_REASONING_EFFORT "${codex_reasoning}" none low medium high xhigh
require_choice CODEX_APPROVAL_POLICY "${codex_approval_policy}" untrusted on-request never
require_choice CODEX_SANDBOX_MODE "${codex_sandbox_mode}" read-only workspace-write danger-full-access

[[ -n "${ollama_base_url}" ]] || fail "OLLAMA_BASE_URL must not be empty"
[[ -n "${codex_model}" ]] || fail "CODEX_MODEL must not be empty"
[[ -n "${codex_model_provider}" ]] || fail "CODEX_MODEL_PROVIDER must not be empty"
[[ -n "${codex_profile}" ]] || fail "CODEX_PROFILE must not be empty"
[[ -n "${codex_catalog_path}" ]] || fail "CODEX_MODEL_CATALOG_PATH must not be empty"

set_env_value USER_UID "${user_uid}"
set_env_value USER_GID "${user_gid}"
set_env_value WORKSPACE_PATH "${workspace_path}"
set_env_value AGENT_HOME_PATH "${agent_home_path}"
set_env_value OLLAMA_BASE_URL "${ollama_base_url}"
set_env_value CODEX_MODEL "${codex_model}"
set_env_value CODEX_MODEL_PROVIDER "${codex_model_provider}"
set_env_value CODEX_MODEL_PROVIDER_NAME "${codex_model_provider_name}"
set_env_value CODEX_PROFILE "${codex_profile}"
set_env_value CODEX_PERSONALITY "${codex_personality}"
set_env_value CODEX_MODEL_REASONING_EFFORT "${codex_reasoning}"
set_env_value CODEX_MODEL_CATALOG_PATH "${codex_catalog_path}"
set_env_value CODEX_APPROVAL_POLICY "${codex_approval_policy}"
set_env_value CODEX_SANDBOX_MODE "${codex_sandbox_mode}"

install -d -m 0755 "${workspace_path}"
install -d -m 0755 "${agent_home_path}"
install -d -m 0700 "${agent_home_path}/.codex"

codex_config="${agent_home_path}/.codex/config.toml"
tmp_config="$(mktemp)"
render_config \
  "${tmp_config}" \
  "$(toml_string "${codex_model}")" \
  "$(toml_string "${codex_model_provider}")" \
  "$(toml_string "${codex_model_provider_name}")" \
  "$(toml_string "${codex_profile}")" \
  "$(toml_string "${codex_personality}")" \
  "$(toml_string "${codex_reasoning}")" \
  "$(toml_string "${ollama_base_url}")" \
  "$(toml_string "${codex_catalog_path}")" \
  "$(toml_string "${codex_approval_policy}")" \
  "$(toml_string "${codex_sandbox_mode}")"

if [[ -f "${codex_config}" ]] && ! cmp -s "${tmp_config}" "${codex_config}"; then
  backup_path="${codex_config}.bak.$(date +%Y%m%d%H%M%S)"
  cp -p "${codex_config}" "${backup_path}"
  echo "Backed up existing Codex config: ${backup_path}"
fi

install -m 0600 "${tmp_config}" "${codex_config}"
rm -f "${tmp_config}"

echo "Workspace: ${workspace_path}"
echo "Agent home: ${agent_home_path}"
echo "Codex config: ${codex_config}"
echo "Ollama endpoint: ${ollama_base_url}"
echo "Model: ${codex_model}"
