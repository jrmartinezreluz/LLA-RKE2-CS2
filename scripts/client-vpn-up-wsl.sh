#!/usr/bin/env bash
# AWS Client VPN (OpenVPN) for WSL — split tunnel to VPC.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="${CLIENT_VPN_CONF:-$ROOT/ansible/client-vpn.ovpn}"
PID_FILE="/run/client-vpn/openvpn.pid"
LOG_FILE="/run/client-vpn/openvpn.log"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Run with sudo: sudo $0" >&2
  exit 1
fi

command -v openvpn >/dev/null || {
  echo "Install OpenVPN: sudo apt update && sudo apt install -y openvpn" >&2
  exit 1
}

[[ -f "$CONF" ]] || {
  echo "Missing profile: $CONF" >&2
  echo "Run: cd $ROOT/terraform && terraform apply  (with enable_client_vpn = true)" >&2
  exit 1
}

mkdir -p /run/client-vpn

if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null && ip link show tun0 &>/dev/null; then
  echo "Client VPN already running (PID $(cat "$PID_FILE"), tun0)."
  exit 0
fi

if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "Stale OpenVPN process (PID $(cat "$PID_FILE")) without tun0 — restarting..."
  kill "$(cat "$PID_FILE")" 2>/dev/null || true
  rm -f "$PID_FILE"
fi

# Stop WireGuard if up — avoid overlapping routes/DNS
if ip link show lla-wg &>/dev/null; then
  echo "Stopping WireGuard (lla-wg) to avoid route conflicts..."
  "$ROOT/scripts/wg-down-wsl.sh" || true
fi

openvpn --config "$CONF" --daemon "lla-client-vpn" --writepid "$PID_FILE" --log "$LOG_FILE"

# TLS + route push can take 10–45s; OpenVPN retries on its own if the network is slow.
for _ in $(seq 1 45); do
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null && ip link show tun0 &>/dev/null; then
    break
  fi
  sleep 1
done
if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null && ip link show tun0 &>/dev/null; then
  echo "AWS Client VPN is up (PID $(cat "$PID_FILE"), tun0)."
  echo "Log: $LOG_FILE"
  echo "Verify:"
  echo "  resolvectl query api.lla.internal"
  echo "  curl -sk -o /dev/null -w '%{http_code}\\n' https://api.lla.internal:6443/version"
  echo "  ssh ubuntu@<master_private_ip> 'echo ok'"
  echo "  kubectl cluster-info   # may work with OpenVPN; else use kubectl-lla.sh"
else
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "OpenVPN still connecting (PID $(cat "$PID_FILE")) — no tun0 yet." >&2
    echo "Leave it retrying, or check: sudo tail -f $LOG_FILE" >&2
    exit 1
  fi
  echo "OpenVPN failed — no tun0 interface. Check: sudo tail -30 $LOG_FILE" >&2
  rm -f "$PID_FILE"
  exit 1
fi

# WSL ignores OpenVPN dhcp-option DNS — point lla.internal at VPC resolver (10.0.0.2).
INTERNAL_DOMAIN="lla.internal"
VPC_DNS="10.0.0.2"
if grep -q '^internal_domain:' "$ROOT/ansible/group_vars/all.yml" 2>/dev/null; then
  INTERNAL_DOMAIN="$(awk -F'"' '/^internal_domain:/{print $2; exit}' "$ROOT/ansible/group_vars/all.yml")"
fi
if command -v resolvectl >/dev/null && ip link show tun0 &>/dev/null; then
  resolvectl dns tun0 "$VPC_DNS" 2>/dev/null || true
  resolvectl domain tun0 "$INTERNAL_DOMAIN" 2>/dev/null || true
fi
RESOLV_LINK_BACKUP="/run/client-vpn/resolv.conf.link"
if [[ -e /etc/resolv.conf ]] && grep -qE 'nameserver[[:space:]]+10\.255\.255\.254' /etc/resolv.conf 2>/dev/null; then
  if [[ -L /etc/resolv.conf ]]; then
    readlink /etc/resolv.conf >"$RESOLV_LINK_BACKUP" 2>/dev/null || true
  elif [[ ! -f "$RESOLV_LINK_BACKUP" ]]; then
    echo "wsl-static" >"$RESOLV_LINK_BACKUP"
  fi
  rm -f /etc/resolv.conf
  cat >/etc/resolv.conf <<EOF
# Managed by client-vpn-up-wsl.sh — restore with client-vpn-down-wsl.sh
nameserver 127.0.0.53
search ${INTERNAL_DOMAIN}
EOF
fi
