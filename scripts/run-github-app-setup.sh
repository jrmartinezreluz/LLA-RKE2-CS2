#!/usr/bin/env bash
# One-shot: SM secret + Argo CD GitHub App (run after aws sso login).
# Set GITHUB_APP_* from your GitHub App settings (see docs/GITHUB-APP-ARGOCD.md).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export AWS_PROFILE="${AWS_PROFILE:-default}"
export AWS_REGION="${AWS_REGION:-us-east-1}"
: "${GITHUB_APP_ID:?Set GITHUB_APP_ID}"
: "${GITHUB_APP_INSTALLATION_ID:?Set GITHUB_APP_INSTALLATION_ID}"
: "${GITHUB_APP_PRIVATE_KEY_FILE:?Set GITHUB_APP_PRIVATE_KEY_FILE to your GitHub App PEM path}"
export GITHUB_ORG_URL="${GITHUB_ORG_URL:-https://github.com/YOUR_ORG}"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"

if ! aws sts get-caller-identity &>/dev/null; then
  echo "Configure AWS credentials (e.g. aws sso login --profile \$AWS_PROFILE)" >&2
  exit 1
fi

if ! aws secretsmanager describe-secret --secret-id lla-rke2-cs2/argocd/github-app &>/dev/null; then
  echo "Creating SM secret + updating ESO IAM policy via terraform..."
  (cd "$ROOT/terraform" && terraform apply \
    -target='module.secrets.aws_secretsmanager_secret.this["argocd_github_app"]' \
    -target='module.secrets.aws_iam_user_policy.external_secrets' \
    -auto-approve)
fi

"$ROOT/scripts/setup-argocd-github-app-secret.sh"

# ESO IAM user must allow GetSecretValue on the new secret ARN.
if ! kubectl -n argocd get externalsecret argocd-github-app-repos &>/dev/null; then
  kubectl apply -f "$ROOT/kubernetes/argocd/external-secret-github-app.yaml"
else
  kubectl annotate externalsecret argocd-github-app-repos -n argocd \
    "force-sync=$(date +%s)" --overwrite 2>/dev/null || true
fi
kubectl -n argocd rollout restart deployment argocd-repo-server
kubectl -n argocd rollout status deployment argocd-repo-server --timeout=120s

sleep 5
kubectl -n argocd get externalsecret argocd-github-app-repos
kubectl -n argocd annotate applicationset erpnext argocd.argoproj.io/application-set-refresh=true --overwrite

echo ""
echo "Waiting for ApplicationSet..."
sleep 10
kubectl -n argocd get applications
kubectl -n argocd describe applicationset erpnext | tail -15
