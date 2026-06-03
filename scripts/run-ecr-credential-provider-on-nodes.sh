#!/usr/bin/env bash
# Install ECR credential provider on all RKE2 nodes (master + workers).
# Requires: VPN/SSH to private IPs, SSH key.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/your-ec2-key-pair.pem}"
SSH_USER="${SSH_USER:-ubuntu}"

resolve_nodes() {
  if [[ -n "${NODES:-}" ]]; then
    echo "$NODES"
    return
  fi
  if [[ ! -d "$ROOT/terraform" ]]; then
    echo "Set NODES=\"<master_ip> <worker_ip> ...\" (from terraform output or inventory)" >&2
    exit 1
  fi
  local master workers
  master="$(cd "$ROOT/terraform" && terraform output -raw master_private_ip 2>/dev/null || true)"
  workers="$(cd "$ROOT/terraform" && terraform output -json worker_private_ips 2>/dev/null \
    | python3 -c 'import json,sys; print(" ".join(json.load(sys.stdin)))' 2>/dev/null || true)"
  if [[ -z "$master" || -z "$workers" ]]; then
    echo "Set NODES=\"<master_ip> <worker_ip> ...\" or run from terraform directory with state available." >&2
    exit 1
  fi
  echo "$master $workers"
}

NODES="$(resolve_nodes)"

SSH_OPTS=(
  -o IPQoS=none
  -o KexAlgorithms=curve25519-sha256
  -o Ciphers=aes128-ctr
  -o Compression=no
  -o ServerAliveInterval=30
  -o ServerAliveCountMax=3
)

for ip in $NODES; do
  echo "========== ${SSH_USER}@${ip} =========="
  ssh "${SSH_OPTS[@]}" -i "$SSH_KEY" "${SSH_USER}@${ip}" 'bash -s' \
    < "$ROOT/scripts/install-ecr-credential-provider.sh"
done

echo "Done. Restart failing ERPNext pods or wait for kubelet retry."
echo "  export KUBECONFIG=~/.kube/lla-rke2.yaml"
echo "  kubectl -n erpnext-dev delete pod -l app.kubernetes.io/name=erpnext --field-selector=status.phase!=Running"
