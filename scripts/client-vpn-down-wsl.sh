#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="/run/client-vpn/openvpn.pid"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Run with sudo: sudo $ROOT/scripts/client-vpn-down-wsl.sh" >&2
  exit 1
fi

if [[ -f "$PID_FILE" ]]; then
  kill "$(cat "$PID_FILE")" 2>/dev/null || true
  rm -f "$PID_FILE"
fi

pkill -f "openvpn.*lla-client-vpn" 2>/dev/null || true
ip link delete tun0 2>/dev/null || true

RESOLV_LINK_BACKUP="/run/client-vpn/resolv.conf.link"
if [[ -f "$RESOLV_LINK_BACKUP" ]]; then
  target="$(cat "$RESOLV_LINK_BACKUP")"
  rm -f /etc/resolv.conf
  if [[ "$target" == "wsl-static" ]]; then
    :
  else
    ln -sf "$target" /etc/resolv.conf
  fi
  rm -f "$RESOLV_LINK_BACKUP"
fi

echo "AWS Client VPN stopped."
