#!/usr/bin/env bash
# Writes ansible/group_vars/all.yml from Terraform outputs (requires jq).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/ansible/group_vars/all.yml"
JSON="$(terraform -chdir="$ROOT/terraform" output -json ansible_vars)"

mkdir -p "$(dirname "$OUT")"

cat > "$OUT" <<EOF
---
vpc_cidr: "$(echo "$JSON" | jq -r '.vpc_cidr')"
wireguard_public_ip: "$(echo "$JSON" | jq -r '.wireguard_public_ip')"
wireguard_vpn_cidr: "10.8.0.0/24"
master_private_ip: "$(echo "$JSON" | jq -r '.master_private_ip')"

worker_private_ips:
$(echo "$JSON" | jq -r '.worker_private_ips[] | "  - \(.)"')

internal_domain: "$(echo "$JSON" | jq -r '.internal_domain')"
api_fqdn: "$(echo "$JSON" | jq -r '.api_fqdn')"
join_fqdn: "$(echo "$JSON" | jq -r '.join_fqdn')"
ingress_fqdn: "$(echo "$JSON" | jq -r '.ingress_fqdn')"
kubernetes_api_url: "$(echo "$JSON" | jq -r '.kubernetes_api_url')"
argocd_fqdn: "$(echo "$JSON" | jq -r '.argocd_fqdn')"
argocd_url: "$(echo "$JSON" | jq -r '.argocd_url')"
grafana_fqdn: "$(echo "$JSON" | jq -r '.grafana_fqdn')"
grafana_url: "$(echo "$JSON" | jq -r '.grafana_url')"

wireguard_port: 51820
wireguard_server_address: "10.8.0.1/24"
wireguard_vpn_cidr: "10.8.0.0/24"
wireguard_peers: []

cluster_token: "{{ lookup('env', 'RKE2_CLUSTER_TOKEN') | default('', true) }}"

ansible_ssh_private_key_file: "~/.ssh/your-key.pem"
EOF

echo "Wrote $OUT"
echo "Next: copy ansible/inventory.ini.example to inventory.ini"
echo "  Phase 1: wireguard public IP | Phase 2 (VPN up): master + worker private IPs"
echo "  terraform -chdir=$ROOT/terraform output"
echo "  terraform -chdir=$ROOT/terraform output"
echo "Internal DNS (after apply):"
echo "  API:     $(echo "$JSON" | jq -r '.kubernetes_api_url')"
echo "  Ingress: https://$(echo "$JSON" | jq -r '.ingress_fqdn')"
