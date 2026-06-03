#!/usr/bin/env bash
# Bootstrap ERPNext DBs from WSL using many small SSH commands (no paste, no scp, no stdin pipe).
set -euo pipefail

WORKER_IP="${WORKER_IP:-}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/your-ec2-key-pair.pem}"
SSH_USER="${SSH_USER:-ubuntu}"
PROJECT="${PROJECT:-lla-rke2-cs2}"
AWS_REGION="${AWS_REGION:-us-east-1}"

if [[ -z "$WORKER_IP" ]]; then
  WORKER_IP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../terraform" 2>/dev/null \
    && terraform output -json worker_private_ips 2>/dev/null \
    | python3 -c 'import json,sys; w=json.load(sys.stdin); print(w[0] if w else "")' 2>/dev/null || true)"
fi
[[ -n "$WORKER_IP" ]] || { echo "Set WORKER_IP from terraform output worker_private_ips" >&2; exit 1; }

SSH_OPTS=(
  -o ConnectTimeout=15
  -o IPQoS=none
  -o KexAlgorithms=curve25519-sha256
  -o Ciphers=aes128-ctr
  -o Compression=no
  -o ServerAliveInterval=10
  -o ServerAliveCountMax=3
)

remote() {
  ssh "${SSH_OPTS[@]}" -i "$SSH_KEY" "${SSH_USER}@${WORKER_IP}" "$@"
}

echo "==> Ping worker (from WSL; start WireGuard if this fails)"
ping -c 1 -W 3 "$WORKER_IP" >/dev/null

echo "==> Ensure mysql client on worker"
remote "command -v mysql >/dev/null || sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mariadb-client jq"

provision_env() {
  local env="$1"
  echo "==> Provisioning ${env}"
  remote "bash -lc $(printf '%q' "
    set -e
    MASTER=\$(aws secretsmanager get-secret-value --region ${AWS_REGION} --secret-id ${PROJECT}/erpnext/rds-master --query SecretString --output text)
    SECRET=\$(aws secretsmanager get-secret-value --region ${AWS_REGION} --secret-id ${PROJECT}/erpnext/${env}/db --query SecretString --output text)
    HOST=\$(echo \"\$MASTER\" | jq -r .host)
    PORT=\$(echo \"\$MASTER\" | jq -r .port)
    ADMIN=\$(echo \"\$MASTER\" | jq -r .username)
    APASS=\$(echo \"\$MASTER\" | jq -r .password)
    DB=\$(echo \"\$SECRET\" | jq -r .database)
    USER=\$(echo \"\$SECRET\" | jq -r .username)
    UPASS=\$(echo \"\$SECRET\" | jq -r .password)
    export MYSQL_PWD=\"\$APASS\"
    mysql -h \"\$HOST\" -P \"\$PORT\" -u \"\$ADMIN\" -e \"
      CREATE DATABASE IF NOT EXISTS \\\`\${DB}\\\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
      CREATE USER IF NOT EXISTS '\${USER}'@'%' IDENTIFIED BY '\${UPASS}';
      GRANT ALL PRIVILEGES ON \\\`\${DB}\\\`.* TO '\${USER}'@'%';
      FLUSH PRIVILEGES;
    \"
    echo OK ${env} db=\${DB} user=\${USER}
  ")"
}

for env in dev stg prod; do
  provision_env "$env"
done

echo "==> Done."
