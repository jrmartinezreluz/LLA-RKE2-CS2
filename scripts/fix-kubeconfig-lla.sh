#!/usr/bin/env bash
# Point kubeconfig server at api.<internal_domain>:6443 (NLB) instead of master private IP.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${1:-${HOME}/.kube/lla-rke2.yaml}"

API_URL="https://api.lla.internal:6443"
if [[ -f "$ROOT/ansible/group_vars/all.yml" ]]; then
  API_URL="$(awk -F'"' '/^kubernetes_api_url:/{print $2; exit}' "$ROOT/ansible/group_vars/all.yml")"
fi

[[ -f "$KUBECONFIG_PATH" ]] || {
  echo "Missing: $KUBECONFIG_PATH" >&2
  echo "Fetch from master: scp ubuntu@<master>:/home/ubuntu/.kube/lla-rke2.yaml $KUBECONFIG_PATH" >&2
  exit 1
}

cp "$KUBECONFIG_PATH" "${KUBECONFIG_PATH}.bak.$(date +%Y%m%d%H%M%S)"
sed -i "s|^[[:space:]]*server:.*|    server: ${API_URL}|" "$KUBECONFIG_PATH"

echo "Updated server → ${API_URL}"
echo "  file: ${KUBECONFIG_PATH}"
echo "Test: KUBECONFIG=${KUBECONFIG_PATH} kubectl cluster-info"
