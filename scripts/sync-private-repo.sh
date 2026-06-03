#!/usr/bin/env bash
# Merge updates from the public LLA-RKE2-CS2 tree into LLA-RKE2-CS2-private without
# overwriting deployment-specific ops files (inventory, group_vars, tfvars, VPN configs).
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${DEST:-${SRC}-private}"

if [[ ! -d "$DEST" ]]; then
  echo "ERROR: private repo not found at $DEST" >&2
  echo "Create it first: scripts/init-private-repo.sh" >&2
  exit 1
fi

if [[ ! -d "$DEST/.git" ]]; then
  echo "ERROR: $DEST is not a git repository" >&2
  exit 1
fi

BACKUP="$(mktemp -d)"
trap 'rm -rf "$BACKUP"' EXIT

preserve() {
  local rel="$1"
  if [[ -f "$DEST/$rel" ]]; then
    mkdir -p "$BACKUP/$(dirname "$rel")"
    cp -a "$DEST/$rel" "$BACKUP/$rel"
    echo "  backup $rel"
  fi
}

echo "Backing up private ops files..."
preserve ansible/group_vars/all.yml
preserve ansible/inventory.ini
preserve terraform/terraform.tfvars
preserve ansible/wg-client.conf
preserve ansible/jose-lla-wg.conf
preserve ansible/jose-lla.conf
preserve ansible/lla-windows-yurani.conf
preserve ansible/client-vpn.ovpn
preserve ansible/client_jose_private.key
preserve ansible/client_jose_public.key
# Optional private-only doc (not in public tree)
preserve terraform/README.md

echo "Syncing from $SRC -> $DEST ..."
rsync -a \
  --exclude '.git/' \
  --exclude '.terraform/' \
  --exclude 'terraform/terraform.tfstate' \
  --exclude 'terraform/terraform.tfstate.backup' \
  --exclude 'terraform/terraform.tfstate.destroyed.*' \
  --exclude '.venv/' \
  --exclude 'ansible/group_vars/all.yml' \
  --exclude 'ansible/inventory.ini' \
  --exclude 'terraform/terraform.tfvars' \
  --exclude 'ansible/wg-client.conf' \
  --exclude 'ansible/jose-lla-wg.conf' \
  --exclude 'ansible/jose-lla.conf' \
  --exclude 'ansible/lla-windows-yurani.conf' \
  --exclude 'ansible/client-vpn.ovpn' \
  --exclude 'ansible/client_jose_private.key' \
  --exclude 'ansible/client_jose_public.key' \
  "$SRC/" "$DEST/"

cp "$DEST/.gitignore.private.example" "$DEST/.gitignore"

restore() {
  local rel="$1"
  if [[ -f "$BACKUP/$rel" ]]; then
    mkdir -p "$DEST/$(dirname "$rel")"
    cp -a "$BACKUP/$rel" "$DEST/$rel"
    echo "  restore $rel"
  fi
}

echo "Restoring private ops files..."
restore ansible/group_vars/all.yml
restore ansible/inventory.ini
restore terraform/terraform.tfvars
restore ansible/wg-client.conf
restore ansible/jose-lla-wg.conf
restore ansible/jose-lla.conf
restore ansible/lla-windows-yurani.conf
restore ansible/client-vpn.ovpn
restore ansible/client_jose_private.key
restore ansible/client_jose_public.key
restore terraform/README.md

echo ""
echo "Done. Review and commit in the private repo:"
echo "  cd $DEST"
echo "  git status"
echo "  git diff"
