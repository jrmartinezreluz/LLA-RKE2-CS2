#!/usr/bin/env bash
# kubectl via SSH tunnel — workaround for Go TLS handshake hangs over WSL+WireGuard.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_SRC="${KUBECONFIG:-${HOME}/.kube/lla-rke2.yaml}"
LOCAL_PORT="${KUBECTL_TUNNEL_PORT:-16443}"
BASTION="${KUBECTL_TUNNEL_BASTION:-}"
API_TARGET="${KUBECTL_TUNNEL_API:-}"

if [[ -z "$BASTION" || -z "$API_TARGET" ]]; then
  echo "Set KUBECTL_TUNNEL_BASTION=ubuntu@<worker_ip> and KUBECTL_TUNNEL_API=<api_private_ip>:6443" >&2
  echo "  (from: terraform output worker_private_ips / kubernetes_api_url)" >&2
  exit 1
fi
TUNNEL_KUBECONFIG="${HOME}/.kube/lla-rke2-tunnel.yaml"
PID_FILE="/tmp/lla-kubectl-tunnel.pid"

usage() {
  cat <<EOF
Usage: $0 {up|down|status|exec}

  up      Start SSH tunnel localhost:${LOCAL_PORT} -> ${API_TARGET} via ${BASTION}
  down    Stop tunnel
  status  Show tunnel state
  exec    Run kubectl with tunneled kubeconfig (starts tunnel if needed)

Env: KUBECONFIG, KUBECTL_TUNNEL_PORT, KUBECTL_TUNNEL_BASTION, KUBECTL_TUNNEL_API
EOF
}

tunnel_up() {
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "Tunnel already running (PID $(cat "$PID_FILE"))"
    return 0
  fi

  ssh -f -N \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=30 \
    -L "${LOCAL_PORT}:${API_TARGET}" \
    "$BASTION"

  # Find the ssh process we just spawned
  pid="$(pgrep -f "ssh -f -N.*${LOCAL_PORT}:${API_TARGET}" | head -1 || true)"
  [[ -n "$pid" ]] || { echo "Failed to start tunnel" >&2; exit 1; }
  echo "$pid" >"$PID_FILE"

  cp "$KUBECONFIG_SRC" "$TUNNEL_KUBECONFIG"
  sed -i "s|^[[:space:]]*server:.*|    server: https://127.0.0.1:${LOCAL_PORT}|" "$TUNNEL_KUBECONFIG"

  echo "Tunnel up: https://127.0.0.1:${LOCAL_PORT} -> ${API_TARGET}"
  echo "Kubeconfig: ${TUNNEL_KUBECONFIG}"
}

tunnel_down() {
  if [[ -f "$PID_FILE" ]]; then
    kill "$(cat "$PID_FILE")" 2>/dev/null || true
    rm -f "$PID_FILE"
  fi
  pkill -f "ssh -f -N.*${LOCAL_PORT}:${API_TARGET}" 2>/dev/null || true
  echo "Tunnel stopped."
}

tunnel_status() {
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "Running (PID $(cat "$PID_FILE")), local port ${LOCAL_PORT}"
  else
    echo "Not running"
  fi
}

cmd="${1:-status}"
case "$cmd" in
  up) tunnel_up ;;
  down) tunnel_down ;;
  status) tunnel_status ;;
  exec)
    tunnel_up
    export KUBECONFIG="$TUNNEL_KUBECONFIG"
    shift
    kubectl "$@"
    ;;
  *) usage; exit 1 ;;
esac
