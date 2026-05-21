#!/usr/bin/env bash
set -euo pipefail

template_name=claude-code
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

need_command awk
need_command date
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

user_uid="${user_uid:-$(id -u)}"
user_gid="${user_gid:-$(id -g)}"
workspace_path="${workspace_path:-${default_base}/workspaces/${template_name}}"
agent_home_path="${agent_home_path:-${default_base}/agent-homes/${template_name}}"

require_absolute_path WORKSPACE_PATH "${workspace_path}"
require_absolute_path AGENT_HOME_PATH "${agent_home_path}"
reject_unsafe_path WORKSPACE_PATH "${workspace_path}"
reject_unsafe_path AGENT_HOME_PATH "${agent_home_path}"

set_env_value USER_UID "${user_uid}"
set_env_value USER_GID "${user_gid}"
set_env_value WORKSPACE_PATH "${workspace_path}"
set_env_value AGENT_HOME_PATH "${agent_home_path}"

install -d -m 0755 "${workspace_path}"
install -d -m 0700 "${agent_home_path}"
install -d -m 0700 "${agent_home_path}/.claude"

claude_state_file="${agent_home_path}/.claude.json"
if [[ ! -f "${claude_state_file}" ]]; then
  first_start_time="$(date -u '+%Y-%m-%dT%H:%M:%S.000Z')"
  printf '{\n  "firstStartTime": "%s"\n}\n' "${first_start_time}" > "${claude_state_file}"
  chmod 0600 "${claude_state_file}"
fi

echo "Workspace: ${workspace_path}"
echo "Agent home: ${agent_home_path}"
echo "Claude state dir: ${agent_home_path}/.claude"
echo "Claude state file: ${claude_state_file}"
