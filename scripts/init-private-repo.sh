#!/usr/bin/env bash
# Create a private ops copy of LLA-RKE2-CS2 with real configs (not for public GitHub).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${DEST:-${ROOT}-private}"
GITHUB_USER="${GITHUB_USER:-jrmartinezreluz}"
REPO_NAME="${REPO_NAME:-LLA-RKE2-CS2-private}"
SSH_HOST="${SSH_HOST:-github-arkhadia}"

echo "Source:  $ROOT"
echo "Dest:    $DEST"
echo "Remote:  git@${SSH_HOST}:${GITHUB_USER}/${REPO_NAME}.git"
echo ""

if [[ -e "$DEST" ]]; then
  echo "ERROR: $DEST already exists. Set DEST= to another path or remove it." >&2
  exit 1
fi

mkdir -p "$DEST"
rsync -a \
  --exclude '.git/' \
  --exclude '.terraform/' \
  --exclude 'terraform/terraform.tfstate' \
  --exclude 'terraform/terraform.tfstate.backup' \
  --exclude '.venv/' \
  "$ROOT/" "$DEST/"

cp "$DEST/.gitignore.private.example" "$DEST/.gitignore"

cd "$DEST"
git init -b main

MISSING=0
check_file() {
  if [[ -f "$1" ]]; then
    echo "  OK   $1"
  else
    echo "  WARN $1 (missing — copy from example or source tree)"
    MISSING=$((MISSING + 1))
  fi
}

echo "Ops files:"
check_file ansible/group_vars/all.yml
check_file ansible/inventory.ini
check_file terraform/terraform.tfvars
if [[ -f ansible/wg-client.conf ]] || [[ -f ansible/jose-lla-wg.conf ]]; then
  echo "  OK   WireGuard client config present"
else
  echo "  WARN No wg-client.conf / jose-lla-wg.conf"
  MISSING=$((MISSING + 1))
fi

git add -A
echo ""
git status -s | head -40
[[ $(git status -s | wc -l) -gt 40 ]] && echo "... (truncated)"

git commit -m "$(cat <<EOF
Private LLA RKE2 ops repository

Includes deployment-specific Ansible and Terraform variables.
Do not make this repository public.
EOF
)"

git remote add origin "git@${SSH_HOST}:${GITHUB_USER}/${REPO_NAME}.git"

echo ""
echo "Done. Next steps:"
echo "  1. Create EMPTY private repo on GitHub: ${GITHUB_USER}/${REPO_NAME}"
echo "  2. cd $DEST"
echo "  3. git push -u origin main"
echo ""
if [[ "$MISSING" -gt 0 ]]; then
  echo "Copy missing ops files from $ROOT before pushing if needed."
fi
