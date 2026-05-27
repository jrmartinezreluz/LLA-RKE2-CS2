#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IFACE="${WG_INTERFACE:-lla-wg}"
PID_FILE="/run/wireguard/${IFACE}.pid"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Run with sudo: sudo $ROOT/scripts/wg-down-wsl.sh" >&2
  exit 1
fi

if [[ -f "$PID_FILE" ]]; then
  kill "$(cat "$PID_FILE")" 2>/dev/null || true
  rm -f "$PID_FILE"
fi

pkill -f "wireguard-go ${IFACE}" 2>/dev/null || true
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
