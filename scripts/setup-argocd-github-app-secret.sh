#!/usr/bin/env bash
# Upload GitHub App credentials to AWS Secrets Manager for Argo CD (ESO → repo-creds).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="${LLA_PROJECT:-lla-rke2-cs2}"
SECRET_ID="${PROJECT}/argocd/github-app"
AWS_REGION="${AWS_REGION:-us-east-1}"

GITHUB_APP_ID="${GITHUB_APP_ID:-}"
GITHUB_APP_INSTALLATION_ID="${GITHUB_APP_INSTALLATION_ID:-}"
GITHUB_APP_PRIVATE_KEY_FILE="${GITHUB_APP_PRIVATE_KEY_FILE:-}"
GITHUB_ORG_URL="${GITHUB_ORG_URL:-https://github.com/jrmartinezreluz}"

usage() {
  cat <<EOF
Usage: GITHUB_APP_ID=... GITHUB_APP_INSTALLATION_ID=... \\
       GITHUB_APP_PRIVATE_KEY_FILE=/path/to.pem \\
       ./scripts/setup-argocd-github-app-secret.sh

Uploads JSON to Secrets Manager: ${SECRET_ID}

See: ${ROOT}/docs/GITHUB-APP-ARGOCD.md
EOF
}

[[ -n "$GITHUB_APP_ID" && -n "$GITHUB_APP_INSTALLATION_ID" && -n "$GITHUB_APP_PRIVATE_KEY_FILE" ]] || {
  usage
  exit 1
}

[[ -f "$GITHUB_APP_PRIVATE_KEY_FILE" ]] || {
  echo "PEM not found: $GITHUB_APP_PRIVATE_KEY_FILE" >&2
  exit 1
}

command -v aws >/dev/null || { echo "aws CLI required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq required" >&2; exit 1; }

PRIVATE_KEY="$(cat "$GITHUB_APP_PRIVATE_KEY_FILE")"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

jq -n \
  --arg url "$GITHUB_ORG_URL" \
  --arg githubAppID "$GITHUB_APP_ID" \
  --arg githubAppInstallationID "$GITHUB_APP_INSTALLATION_ID" \
  --arg githubAppPrivateKey "$PRIVATE_KEY" \
  '{url: $url, githubAppID: $githubAppID, githubAppInstallationID: $githubAppInstallationID, githubAppPrivateKey: $githubAppPrivateKey}' \
  >"$TMP"

if ! aws secretsmanager describe-secret --secret-id "$SECRET_ID" --region "$AWS_REGION" &>/dev/null; then
  echo "Secret $SECRET_ID not found. Run: cd $ROOT/terraform && terraform apply" >&2
  exit 1
fi

aws secretsmanager put-secret-value \
  --secret-id "$SECRET_ID" \
  --secret-string "file://$TMP" \
  --region "$AWS_REGION"

echo "Updated Secrets Manager: $SECRET_ID"
echo "Next (cluster):"
echo "  kubectl apply -f $ROOT/kubernetes/argocd/external-secret-github-app.yaml"
echo "  kubectl -n argocd rollout restart deployment argocd-repo-server"
echo "  kubectl -n argocd annotate applicationset erpnext argocd.argoproj.io/application-set-refresh=true --overwrite"
