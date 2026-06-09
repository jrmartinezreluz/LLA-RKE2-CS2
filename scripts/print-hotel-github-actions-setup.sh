#!/usr/bin/env bash
# Print GitHub Actions setup steps for hotel-app after terraform apply.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/terraform"

ROLE_ARN="$(terraform output -raw hotel_github_actions_role_arn 2>/dev/null || true)"
ECR_BACKEND="$(terraform output -json erpnext_ecr_repository_urls 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("hotel-backend",""))' 2>/dev/null || true)"
ECR_FRONTEND="$(terraform output -json erpnext_ecr_repository_urls 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("hotel-frontend",""))' 2>/dev/null || true)"

if [[ -z "$ROLE_ARN" || "$ROLE_ARN" == "null" ]]; then
  echo "Run terraform apply with enable_erpnext_ecr=true and ECR repos hotel-backend, hotel-frontend." >&2
  exit 1
fi

cat <<EOF
GitHub Actions setup for hotel-app
==================================

Repository: https://github.com/jrmartinezreluz/hotel-app
SSH remote: git@github-arkhadia:jrmartinezreluz/hotel-app.git

1. Repository secrets (Settings → Secrets → Actions):
   https://github.com/jrmartinezreluz/hotel-app/settings/secrets/actions

   Name           Value
   ----           -----
   AWS_ROLE_ARN   ${ROLE_ARN}
   GITOPS_PAT     Classic PAT scope "repo", or fine-grained write on platform-gitops

3. Push branches to trigger deploy:

   git push origin dev    # -> hotel-dev (deploy to inactive slot)
   git push origin stg    # -> hotel-stg
   git push origin main   # -> hotel prod

4. After preview looks good:
   Actions → "Promote blue/green" → choose environment

5. ECR repositories:
   backend:  ${ECR_BACKEND:-<add hotel-backend to erpnext_ecr_repositories>}
   frontend: ${ECR_FRONTEND:-<add hotel-frontend to erpnext_ecr_repositories>}

Image tags: sha-<commit> (backend), sha-<commit>-blue|green (frontend inactive slot)
GitOps path: clusters/lla-cs2/hotel/{dev|stg|prod}.yaml

Ensure Argo CD ApplicationSet is applied:
  kubectl apply -f platform-gitops/argocd/applicationsets/hotel.yaml
EOF
