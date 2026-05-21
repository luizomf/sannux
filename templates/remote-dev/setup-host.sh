#!/usr/bin/env bash
set -euo pipefail

template_name=remote-dev
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

set_toml_top_level_value() {
  local file="$1"
  local key="$2"
  local line="$3"
  local tmp
  tmp="$(mktemp)"

  awk -v key="${key}" -v line="${line}" '
    BEGIN {
      in_top_level = 1
      wrote = 0
    }
    in_top_level && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      if (!wrote) {
        print line
        wrote = 1
      }
      next
    }
    $0 ~ "^[[:space:]]*\\[" {
      if (!wrote) {
        print line
        wrote = 1
      }
      in_top_level = 0
    }
    { print }
    END {
      if (!wrote) {
        print line
      }
    }
  ' "${file}" > "${tmp}"

  mv "${tmp}" "${file}"
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
        fail "${key} must point to a dedicated directory outside the repo checkout: ${value}"
        ;;
    esac
  fi
}

prune_known_host() {
  local host="$1"
  local port="$2"
  local known_hosts="$3"
  local target="${host}"

  if [[ "${port}" != 22 ]]; then
    target="[${host}]:${port}"
  fi

  if ssh-keygen -F "${target}" -f "${known_hosts}" >/dev/null 2>&1; then
    ssh-keygen -R "${target}" -f "${known_hosts}" >/dev/null
    rm -f "${known_hosts}.old"
    echo "Removed stale SSH host key for ${target} from ${known_hosts}"
  fi
}

need_command awk
need_command docker
need_command ssh
need_command ssh-keygen

if [[ ! -f "${env_file}" ]]; then
  install -m 0600 "${example_file}" "${env_file}"
  echo "Created ${env_file}"
fi

default_base="${HOME}/sannux-data"
workspace_path="$(get_env_value WORKSPACE_PATH)"
agent_home_path="$(get_env_value AGENT_HOME_PATH)"
host_ssh_port="$(get_env_value HOST_SSH_PORT)"
ssh_bind_address="$(get_env_value SSH_BIND_ADDRESS)"
ssh_host_alias="$(get_env_value SSH_HOST_ALIAS)"
remote_user="$(get_env_value REMOTE_USER)"
user_uid="$(get_env_value USER_UID)"
user_gid="$(get_env_value USER_GID)"

workspace_path="${workspace_path:-${default_base}/workspaces/${template_name}}"
agent_home_path="${agent_home_path:-${default_base}/agent-homes/${template_name}}"
host_ssh_port="${host_ssh_port:-2222}"
ssh_bind_address="${ssh_bind_address:-127.0.0.1}"
ssh_host_alias="${ssh_host_alias:-sannux-remote-dev}"
remote_user="${remote_user:-agent}"
user_uid="${user_uid:-$(id -u)}"
user_gid="${user_gid:-$(id -g)}"

case "${remote_user}" in
  ""|root|*[!a-zA-Z0-9_-]*)
    fail "REMOTE_USER must be a non-root Linux username using letters, numbers, underscore, or dash: ${remote_user}"
    ;;
esac

case "${remote_user}" in
  [0-9]*|-*)
    fail "REMOTE_USER must not start with a digit or dash: ${remote_user}"
    ;;
esac

require_absolute_path WORKSPACE_PATH "${workspace_path}"
require_absolute_path AGENT_HOME_PATH "${agent_home_path}"
reject_unsafe_path WORKSPACE_PATH "${workspace_path}"
reject_unsafe_path AGENT_HOME_PATH "${agent_home_path}"

set_env_value USER_UID "${user_uid}"
set_env_value USER_GID "${user_gid}"
set_env_value REMOTE_USER "${remote_user}"
set_env_value WORKSPACE_PATH "${workspace_path}"
set_env_value AGENT_HOME_PATH "${agent_home_path}"
set_env_value SSH_BIND_ADDRESS "${ssh_bind_address}"
set_env_value HOST_SSH_PORT "${host_ssh_port}"
set_env_value SSH_HOST_ALIAS "${ssh_host_alias}"

install -d -m 0755 "${workspace_path}"
install -d -m 0755 "${agent_home_path}"
install -d -m 0700 "${agent_home_path}/.ssh"
install -d -m 0700 "${agent_home_path}/.codex"
install -d -m 0700 "${agent_home_path}/.codex/app-server-control"

codex_config="${agent_home_path}/.codex/config.toml"
touch "${codex_config}"
chmod 0600 "${codex_config}"
set_toml_top_level_value \
  "${codex_config}" \
  sandbox_mode \
  'sandbox_mode = "danger-full-access"'

host_ssh_dir="${HOME}/.ssh"
sannux_ssh_dir="${host_ssh_dir}/sannux"
key_path="${sannux_ssh_dir}/${template_name}_ed25519"
known_hosts_path="${sannux_ssh_dir}/known_hosts"
ssh_config="${host_ssh_dir}/config"

install -d -m 0700 "${sannux_ssh_dir}"

if [[ ! -f "${key_path}" ]]; then
  ssh-keygen -q -t ed25519 -C "sannux ${template_name}" -f "${key_path}" -N ''
  echo "Created SSH key: ${key_path}"
fi

touch "${known_hosts_path}"
chmod 0600 "${known_hosts_path}"
prune_known_host "${ssh_bind_address}" "${host_ssh_port}" "${known_hosts_path}"
prune_known_host "${ssh_host_alias}" "${host_ssh_port}" "${known_hosts_path}"

authorized_keys="${agent_home_path}/.ssh/authorized_keys"
managed_begin="# BEGIN sannux ${template_name}"
managed_end="# END sannux ${template_name}"
tmp_authorized="$(mktemp)"

if [[ -f "${authorized_keys}" ]]; then
  awk -v begin="${managed_begin}" -v end="${managed_end}" '
    $0 == begin { skip = 1; next }
    $0 == end { skip = 0; next }
    !skip { print }
  ' "${authorized_keys}" > "${tmp_authorized}"
else
  : > "${tmp_authorized}"
fi

{
  cat "${tmp_authorized}"
  echo "${managed_begin}"
  cat "${key_path}.pub"
  echo "${managed_end}"
} > "${authorized_keys}"
rm -f "${tmp_authorized}"
chmod 0600 "${authorized_keys}"

install -d -m 0700 "${host_ssh_dir}"
tmp_config="$(mktemp)"
config_begin="# BEGIN sannux ${template_name}"
config_end="# END sannux ${template_name}"

if [[ -f "${ssh_config}" ]]; then
  awk -v begin="${config_begin}" -v end="${config_end}" '
    $0 == begin { skip = 1; next }
    $0 == end { skip = 0; next }
    !skip { print }
  ' "${ssh_config}" > "${tmp_config}"
else
  : > "${tmp_config}"
fi

{
  cat "${tmp_config}"
  echo "${config_begin}"
  echo "Host ${ssh_host_alias}"
  echo "  HostName ${ssh_bind_address}"
  echo "  Port ${host_ssh_port}"
  echo "  User ${remote_user}"
  echo "  IdentityFile ${key_path}"
  echo "  IdentitiesOnly yes"
  echo "  StrictHostKeyChecking accept-new"
  echo "  UserKnownHostsFile ${known_hosts_path}"
  echo "${config_end}"
} > "${ssh_config}"
rm -f "${tmp_config}"
chmod 0600 "${ssh_config}"

echo "Building and starting ${template_name} SSH..."
(
  cd "${template_dir}"
  docker compose build
  docker compose --profile daemon up -d ssh
)

echo "Testing SSH connection..."
ssh_output=""
for attempt in {1..20}; do
  if ssh_output="$(ssh -F "${ssh_config}" -o BatchMode=yes "${ssh_host_alias}" 'printf "connected: %s %s\n" "$(id -un)" "$(pwd)"' 2>&1)"; then
    echo "${ssh_output}"
    break
  fi
  if [[ "${attempt}" == 20 ]]; then
    echo "${ssh_output}" >&2
    fail "SSH service started, but the connection test failed."
  fi
  sleep 1
done

cat <<EOF

Remote dev is ready.

Use this SSH host in Codex, Antigravity, VS Code, or any Remote SSH app:

  ${ssh_host_alias}

Open this folder in the app:

  /workspace

The app stays local. Its remote server, commands, caches, and project access run
inside the sannux container.
EOF
