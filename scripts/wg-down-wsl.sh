#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
[[ -f "$ROOT/scripts/wg-defaults.env" ]] && source "$ROOT/scripts/wg-defaults.env"
IFACE="${WG_INTERFACE:-lla-wg}"
PID_FILE="/run/wireguard/${IFACE}.pid"
MSS_FLAG="/run/wireguard/${IFACE}.mss-clamp"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Run with sudo: sudo $ROOT/scripts/wg-down-wsl.sh" >&2
  exit 1
fi

if [[ -f "$PID_FILE" ]]; then
  kill "$(cat "$PID_FILE")" 2>/dev/null || true
  rm -f "$PID_FILE"
fi

pkill -f "wireguard-go ${IFACE}" 2>/dev/null || true

if [[ -f "$MSS_FLAG" ]] && command -v iptables >/dev/null; then
  iptables -t mangle -D OUTPUT -o "$IFACE" -p tcp -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
  iptables -t mangle -D OUTPUT -o "$IFACE" -j DSCP --set-dscp 0 2>/dev/null || true
  rm -f "$MSS_FLAG"
fi

ip link delete "$IFACE" 2>/dev/null || true

# Restore WSL resolv.conf if we replaced it for lla.internal
RESOLV_LINK_BACKUP="/run/wireguard/resolv.conf.link"
if [[ -f "$RESOLV_LINK_BACKUP" ]]; then
  target="$(cat "$RESOLV_LINK_BACKUP")"
  rm -f /etc/resolv.conf
  if [[ "$target" == "wsl-static" ]]; then
    : # leave WSL to regenerate on next boot, or user fixes manually
  else
    ln -sf "$target" /etc/resolv.conf
  fi
  rm -f "$RESOLV_LINK_BACKUP"
fi

echo "Tunnel ${IFACE} stopped."
