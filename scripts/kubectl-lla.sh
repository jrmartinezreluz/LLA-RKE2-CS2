#!/usr/bin/env bash
# Run kubectl on the RKE2 master via SSH — reliable from WSL + WireGuard.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
resolve_master() {
  if [[ -n "${KUBECTL_LLA_MASTER:-}" ]]; then
    echo "$KUBECTL_LLA_MASTER"
    return
  fi
  local ip
  ip="$(cd "$ROOT/terraform" 2>/dev/null && terraform output -raw master_private_ip 2>/dev/null || true)"
  if [[ -n "$ip" ]]; then
    echo "ubuntu@${ip}"
    return
  fi
  echo "Set KUBECTL_LLA_MASTER=ubuntu@<master_private_ip>" >&2
  exit 1
}
MASTER="$(resolve_master)"

usage() {
  cat <<EOF
Usage: $0 [kubectl args...]

Runs kubectl on ${MASTER}. Local -f/--filename files use base64 over SSH (WSL-safe; no scp/stdin pipe).

Examples:
  $0 get nodes
  $0 apply -f platform-gitops/argocd/projects/apps.yaml
  $0 apply --server-side --force-conflicts -f kubernetes/argocd/

Env: KUBECTL_LLA_MASTER
EOF
}

[[ $# -eq 0 ]] && { usage; exit 1; }

remote_kubectl() {
  ssh -o ConnectTimeout=20 "$MASTER" \
    "sudo KUBECONFIG=/etc/rancher/rke2/rke2.yaml kubectl $(printf '%q ' "$@")"
}

# Collect local files from -f / --filename.
local_files=()
remote_args=()
i=1
while [[ $i -le $# ]]; do
  a="${!i}"
  if [[ "$a" == "-f" || "$a" == "--filename" ]]; then
    n=$((i + 1))
    p="${!n}"
    if [[ -f "$p" ]]; then
      local_files+=("$p")
      i=$((n + 1))
      continue
    fi
  fi
  remote_args+=("$a")
  i=$((i + 1))
done

if [[ ${#local_files[@]} -eq 0 ]]; then
  remote_kubectl "$@"
  exit $?
fi

for f in "${local_files[@]}"; do
  echo "→ ${f}" >&2
  b64="$(base64 -w0 "$f")"
  remote="/tmp/lla-kubectl-$(basename "$f").yaml"
  ssh -o ConnectTimeout=20 "$MASTER" \
    "echo ${b64} | base64 -d > ${remote} && sudo KUBECONFIG=/etc/rancher/rke2/rke2.yaml kubectl $(printf '%q ' "${remote_args[@]}") -f ${remote}"
done
