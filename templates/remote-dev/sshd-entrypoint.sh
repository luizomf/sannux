#!/usr/bin/env bash
set -euo pipefail

remote_user="${REMOTE_USER:-agent}"
remote_home="$(getent passwd "${remote_user}" | cut -d: -f6)"
remote_group="$(id -gn "${remote_user}")"
ssh_dir="${remote_home}/.ssh"
authorized_keys="${ssh_dir}/authorized_keys"
host_ed25519="${ssh_dir}/sshd_host_ed25519_key"
host_rsa="${ssh_dir}/sshd_host_rsa_key"
tmp_sshd_config=/run/sshd/sannux_sshd_config

install -d -m 0755 /run/sshd
install -d -m 0700 -o "${remote_user}" -g "${remote_group}" "${ssh_dir}"

if [[ ! -s "${authorized_keys}" ]]; then
  cat >&2 <<'EOF'
Missing the remote user's .ssh/authorized_keys.
Run `just setup remote-dev` from the sannux repo root, or run ./setup-host.sh
from this template folder, before starting the ssh service.
EOF
  exit 1
fi

chown "${remote_user}:${remote_group}" "${authorized_keys}"
chmod 0600 "${authorized_keys}"

if [[ ! -f "${host_ed25519}" ]]; then
  ssh-keygen -q -t ed25519 -f "${host_ed25519}" -N ''
fi

if [[ ! -f "${host_rsa}" ]]; then
  ssh-keygen -q -t rsa -b 4096 -f "${host_rsa}" -N ''
fi

chown root:root "${host_ed25519}" "${host_ed25519}.pub" "${host_rsa}" "${host_rsa}.pub"
chmod 0600 "${host_ed25519}" "${host_rsa}"
chmod 0644 "${host_ed25519}.pub" "${host_rsa}.pub"
chown -R "${remote_user}:${remote_group}" "${remote_home}"
chown root:root "${host_ed25519}" "${host_ed25519}.pub" "${host_rsa}" "${host_rsa}.pub"

sed \
  -e "s#__REMOTE_USER__#${remote_user}#g" \
  -e "s#__REMOTE_HOME__#${remote_home}#g" \
  /etc/ssh/sshd_config > "${tmp_sshd_config}"
mv "${tmp_sshd_config}" /etc/ssh/sshd_config

exec /usr/sbin/sshd -D -e -f /etc/ssh/sshd_config
