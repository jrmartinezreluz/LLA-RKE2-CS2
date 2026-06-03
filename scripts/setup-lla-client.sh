#!/usr/bin/env bash
# One-time WSL client setup: SSH, kubeconfig URL, optional VPN reminder.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> SSH config (LLA VPC hosts)"
"$ROOT/scripts/install-ssh-lla-config.sh"

echo ""
echo "==> Kubeconfig server URL (for reference; use kubectl-lla.sh from WSL)"
if [[ -f "${HOME}/.kube/lla-rke2.yaml" ]]; then
  "$ROOT/scripts/fix-kubeconfig-lla.sh" "${HOME}/.kube/lla-rke2.yaml"
else
  echo "Skip: ${HOME}/.kube/lla-rke2.yaml not found"
  echo "Fetch: scp ubuntu@<master_private_ip>:/home/ubuntu/.kube/lla-rke2.yaml ~/.kube/lla-rke2.yaml"
fi

chmod +x "$ROOT/scripts/kubectl-lla.sh" "$ROOT/scripts/wg-up-wsl.sh" "$ROOT/scripts/wg-down-wsl.sh"
chmod +x "$ROOT/scripts/client-vpn-up-wsl.sh" "$ROOT/scripts/client-vpn-down-wsl.sh" 2>/dev/null || true

cat <<EOF

==> Done. Daily workflow (WSL):

  Option A — AWS Client VPN (recommended after terraform apply):
    sudo apt install -y openvpn
    sudo $ROOT/scripts/client-vpn-up-wsl.sh

  Option B — WireGuard (legacy):
    sudo $ROOT/scripts/wg-up-wsl.sh

  kubectl:  $ROOT/scripts/kubectl-lla.sh get nodes
  See: $ROOT/docs/CLIENT-VPN.md

EOF
