#!/usr/bin/env bash
# Print GitHub Actions setup steps after terraform apply.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/terraform"

ROLE_ARN="$(terraform output -raw erpnext_github_actions_role_arn 2>/dev/null || true)"
ECR_URL="$(terraform output -json erpnext_ecr_repository_urls 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("erpnext",""))' 2>/dev/null || true)"

if [[ -z "$ROLE_ARN" || "$ROLE_ARN" == "null" ]]; then
  echo "Run terraform apply with enable_erpnext_ecr=true first." >&2
  exit 1
fi

cat <<EOF
GitHub Actions setup for erpnext-app
====================================

1. Repository secrets (NOT environment secrets):
   https://github.com/jrmartinezreluz/erpnext-app/settings/secrets/actions

   Name           Value
   ----           -----
   AWS_ROLE_ARN   ${ROLE_ARN}
   GITOPS_PAT     Classic PAT: scope "repo" (full control of private repos)
                  Fine-grained: Contents Read+Write on platform-gitops only
                  Create: https://github.com/settings/tokens

   If GITOPS_PAT is wrong, git clone fails with:
   "Invalid username or token. Password authentication is not supported"

2. Push to trigger build:

   git push origin dev    # -> erpnext-dev
   git push origin stg    # -> erpnext-stg
   git push origin main   # -> erpnext prod

3. ECR repository: ${ECR_URL:-<run terraform output erpnext_ecr_repository_urls>}

Image tag format: sha-<commit>
GitOps updates: clusters/lla-cs2/erpnext/{dev|stg|prod}.yaml
EOF
