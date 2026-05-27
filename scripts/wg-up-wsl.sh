#!/usr/bin/env bash
# WireGuard client for WSL — bypasses wg-quick kernel hang via wireguard-go TUN.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="${WG_CONF:-$ROOT/ansible/wg-client.conf}"
IFACE="${WG_INTERFACE:-lla-wg}"
PID_FILE="/run/wireguard/${IFACE}.pid"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Run with sudo: sudo $ROOT/scripts/wg-up-wsl.sh" >&2
  exit 1
fi

for cmd in wireguard-go wg wg-quick ip; do
  command -v "$cmd" >/dev/null || { echo "Missing: $cmd" >&2; exit 1; }
done

[[ -f "$CONF" ]] || { echo "Missing config: $CONF" >&2; exit 1; }
chmod 600 "$CONF"

mkdir -p /run/wireguard

# Tear down previous session
if [[ -f "$PID_FILE" ]]; then
  kill "$(cat "$PID_FILE")" 2>/dev/null || true
  rm -f "$PID_FILE"
fi
ip link delete "$IFACE" 2>/dev/null || true
pkill -f "wireguard-go ${IFACE}" 2>/dev/null || true
sleep 1

# Start userspace WireGuard (creates TUN — no kernel module required)
wireguard-go "$IFACE" &
echo $! > "$PID_FILE"
sleep 1

if ! ip link show "$IFACE" >/dev/null 2>&1; then
  echo "Failed to create interface $IFACE via wireguard-go" >&2
  exit 1
fi

wg setconf "$IFACE" <(wg-quick strip "$CONF")

# Address from config
ADDR="$(awk -F' = ' '/^Address/{print $2; exit}' "$CONF" | tr -d ' ')"
ip addr flush dev "$IFACE" 2>/dev/null || true
ip addr add "$ADDR" dev "$IFACE"
ip link set mtu 1420 up dev "$IFACE"

# Routes from AllowedIPs (Peer section)
ALLOWED="$(awk -F' = ' '/^AllowedIPs/{print $2; exit}' "$CONF" | tr -d ' ')"
IFS=',' read -ra ROUTES <<< "$ALLOWED"
for route in "${ROUTES[@]}"; do
  ip route replace "$route" dev "$IFACE"
done

# DNS: Route53 private zone resolves only via VPC resolver (10.0.0.2).
INTERNAL_DOMAIN="lla.internal"
if grep -q '^internal_domain:' "$ROOT/ansible/group_vars/all.yml" 2>/dev/null; then
  INTERNAL_DOMAIN="$(awk -F'"' '/^internal_domain:/{print $2; exit}' "$ROOT/ansible/group_vars/all.yml")"
fi

DNS="$(awk -F' = ' '/^DNS/{print $2; exit}' "$CONF" | tr -d ' ' || true)"
if [[ -n "${DNS:-}" ]] && command -v resolvectl >/dev/null; then
  resolvectl dns "$IFACE" "$DNS" 2>/dev/null || true
  resolvectl domain "$IFACE" "$INTERNAL_DOMAIN" 2>/dev/null || true
fi

# WSL ships resolv.conf with 10.255.255.254 (foreign mode). libc/curl/browser
# ignore systemd-resolved split DNS; point resolv.conf at the resolved stub.
RESOLV_LINK_BACKUP="/run/wireguard/resolv.conf.link"
if [[ -e /etc/resolv.conf ]] && grep -qE 'nameserver[[:space:]]+10\.255\.255\.254' /etc/resolv.conf 2>/dev/null; then
  if [[ -L /etc/resolv.conf ]]; then
    readlink /etc/resolv.conf >"$RESOLV_LINK_BACKUP" 2>/dev/null || true
  elif [[ ! -f "$RESOLV_LINK_BACKUP" ]]; then
    echo "wsl-static" >"$RESOLV_LINK_BACKUP"
  fi
  rm -f /etc/resolv.conf
  cat >/etc/resolv.conf <<EOF
# Managed by wg-up-wsl.sh — restore with wg-down-wsl.sh
nameserver 127.0.0.53
search ${INTERNAL_DOMAIN}
EOF
fi

echo ""
echo "Tunnel ${IFACE} is up (wireguard-go, PID $(cat "$PID_FILE"))."
echo "Verify:"
echo "  sudo wg show"
echo "  resolvectl query argocd.${INTERNAL_DOMAIN}"
echo "  curl -sS -o /dev/null -w '%{http_code}\\n' http://argocd.${INTERNAL_DOMAIN}/"
echo "  ping -c 3 <master_private_ip>"
echo "  ssh -i ~/.ssh/<your-ec2-key>.pem ubuntu@<master_private_ip>"
echo ""
echo "To stop: sudo $ROOT/scripts/wg-down-wsl.sh"
