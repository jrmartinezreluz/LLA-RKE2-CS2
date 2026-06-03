#!/usr/bin/env bash
# Run ERPNext RDS bootstrap ON the worker without copying a file (avoids scp/cat hangs).
# Requires: WireGuard up, worker reachable, terraform IAM for erpnext secrets on nodes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKER_IP="${WORKER_IP:-}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/your-ec2-key-pair.pem}"
SSH_USER="${SSH_USER:-ubuntu}"

if [[ -z "$WORKER_IP" ]]; then
  WORKER_IP="$(cd "$ROOT/terraform" 2>/dev/null \
    && terraform output -json worker_private_ips 2>/dev/null \
    | python3 -c 'import json,sys; w=json.load(sys.stdin); print(w[0] if w else "")' 2>/dev/null || true)"
fi
[[ -n "$WORKER_IP" ]] || { echo "Set WORKER_IP from terraform output worker_private_ips" >&2; exit 1; }

SSH_OPTS=(
  -o IPQoS=none
  -o KexAlgorithms=curve25519-sha256
  -o Ciphers=aes128-ctr
  -o Compression=no
  -o ServerAliveInterval=30
  -o ServerAliveCountMax=3
)

echo "Running bootstrap on ${SSH_USER}@${WORKER_IP} via stdin (no remote file copy)..."
ssh "${SSH_OPTS[@]}" -i "$SSH_KEY" "${SSH_USER}@${WORKER_IP}" 'bash -s' \
  < "$ROOT/scripts/bootstrap-erpnext-rds-databases.sh"
echo "Bootstrap finished."
