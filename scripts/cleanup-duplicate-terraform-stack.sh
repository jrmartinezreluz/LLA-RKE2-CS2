#!/usr/bin/env bash
# Destroys the accidental second VPC/stack created by "terraform apply" in
# LLA-RKE2-CS2-private/terraform (empty/wrong state). Does NOT touch
# LLA-RKE2-CS2/terraform — that is the canonical cluster state.
set -euo pipefail

WRONG_DIR="${1:-/ark/LLA-RKE2-CS2-private/terraform}"
CANONICAL_DIR="/ark/LLA-RKE2-CS2/terraform"

if [[ ! -f "${WRONG_DIR}/terraform.tfstate" ]]; then
  echo "No terraform.tfstate in ${WRONG_DIR} — nothing to destroy."
  exit 0
fi

echo "WARNING: This will DESTROY AWS resources tracked only in:"
echo "  ${WRONG_DIR}/terraform.tfstate"
echo ""
echo "It will NOT modify the real cluster state in:"
echo "  ${CANONICAL_DIR}/terraform.tfstate"
echo ""
terraform -chdir="${WRONG_DIR}" state list | head -20
echo "..."
echo ""
read -r -p "Type 'destroy-duplicate' to continue: " confirm
if [[ "${confirm}" != "destroy-duplicate" ]]; then
  echo "Aborted."
  exit 1
fi

terraform -chdir="${WRONG_DIR}" destroy

echo ""
echo "Optional: archive the wrong state so it is not reused:"
echo "  mv ${WRONG_DIR}/terraform.tfstate ${WRONG_DIR}/terraform.tfstate.destroyed.\$(date +%Y%m%d)"
