#!/usr/bin/env bash
# Install ~/.ssh/ssh-lla.conf for stable SSH/scp/git over WireGuard from WSL.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${HOME}/.ssh/ssh-lla.conf"
INCLUDE_LINE="Include ${DEST}"

mkdir -p "${HOME}/.ssh"
chmod 700 "${HOME}/.ssh"
cp "$ROOT/scripts/ssh-lla.conf.example" "$DEST"
chmod 600 "$DEST"

INCLUDE_ABS="${DEST}"
if [[ -f "${HOME}/.ssh/config" ]] && grep -qF "$INCLUDE_ABS" "${HOME}/.ssh/config"; then
  echo "Already included in ~/.ssh/config"
elif [[ -f "${HOME}/.ssh/config" ]] && grep -q 'ssh-lla.conf' "${HOME}/.ssh/config"; then
  sed -i "s|^[[:space:]]*Include.*ssh-lla.conf|Include ${INCLUDE_ABS}|" "${HOME}/.ssh/config"
  echo "Updated Include path in ~/.ssh/config"
else
  # Include must be first — OpenSSH applies first Host match; tilde in Include may not expand.
  tmp="$(mktemp)"
  { echo "Include ${INCLUDE_ABS}"; echo ""; cat "${HOME}/.ssh/config" 2>/dev/null || true; } >"$tmp"
  mv "$tmp" "${HOME}/.ssh/config"
  chmod 600 "${HOME}/.ssh/config"
  echo "Prepended Include ${INCLUDE_ABS} to ~/.ssh/config"
fi

echo "Installed $DEST"
echo "Test: ssh ubuntu@<worker_private_ip> 'echo ok'"
