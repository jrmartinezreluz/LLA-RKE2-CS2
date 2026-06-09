#!/usr/bin/env bash
# Initialize and push hotel-app to GitHub.
# Usage: ./scripts/push-hotel-app.sh
set -euo pipefail

GITHUB_SSH_HOST="${GITHUB_SSH_HOST:-github-arkhadia}"
GITHUB_ORG="${GITHUB_ORG:-jrmartinezreluz}"
REPO_NAME="hotel-app"
# hotel-app lives next to LLA-RKE2-CS2 under /ark (not inside LLA-RKE2-CS2)
ARK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOTEL_APP_DIR="${HOTEL_APP_DIR:-${ARK_ROOT}/hotel-app}"
URL="git@${GITHUB_SSH_HOST}:${GITHUB_ORG}/${REPO_NAME}.git"

echo ">>> ${REPO_NAME} → ${URL}"
if [[ ! -d "$HOTEL_APP_DIR" ]]; then
  echo "hotel-app not found at ${HOTEL_APP_DIR}" >&2
  echo "Set HOTEL_APP_DIR or clone layout: /ark/hotel-app" >&2
  exit 1
fi
cd "$HOTEL_APP_DIR"

if [[ ! -d .git ]]; then
  git init -b main
fi

if ! git remote get-url origin &>/dev/null; then
  git remote add origin "$URL"
else
  git remote set-url origin "$URL"
fi

git add -A
if git diff --cached --quiet; then
  echo "    Nothing to commit"
else
  git commit -m "Hotel app with blue/green GitHub Actions"
fi

git push -u origin main

for branch in dev stg; do
  git checkout -B "$branch"
  git push -u origin "$branch"
done

git checkout main
echo ""
echo "Done. Next:"
echo "  LLA-RKE2-CS2/scripts/print-hotel-github-actions-setup.sh"
echo "  Set AWS_ROLE_ARN + GITOPS_PAT on https://github.com/${GITHUB_ORG}/${REPO_NAME}/settings/secrets/actions"
