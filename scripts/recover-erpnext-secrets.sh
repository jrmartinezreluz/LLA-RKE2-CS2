#!/usr/bin/env bash
# Remove ERPNext secrets stuck in "scheduled for deletion" after duplicate-stack destroy.
# Then run: cd terraform && terraform apply
set -euo pipefail

PROJECT="${PROJECT:-lla-rke2-cs2}"
AWS_REGION="${AWS_REGION:-us-east-1}"

SECRETS=(
  "${PROJECT}/erpnext/rds-master"
  "${PROJECT}/erpnext/dev/db"
  "${PROJECT}/erpnext/stg/db"
  "${PROJECT}/erpnext/prod/db"
  "${PROJECT}/erpnext/dev/admin"
  "${PROJECT}/erpnext/stg/admin"
  "${PROJECT}/erpnext/prod/admin"
)

for name in "${SECRETS[@]}"; do
  if aws secretsmanager describe-secret --region "$AWS_REGION" --secret-id "$name" &>/dev/null; then
    echo "Force-delete: $name"
    aws secretsmanager delete-secret \
      --region "$AWS_REGION" \
      --secret-id "$name" \
      --force-delete-without-recovery
  else
    echo "Not found (OK): $name"
  fi
done

echo ""
echo "Done. Re-run: cd LLA-RKE2-CS2/terraform && terraform apply"
