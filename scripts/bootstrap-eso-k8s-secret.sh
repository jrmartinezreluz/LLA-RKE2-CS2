#!/usr/bin/env bash
# Creates kubernetes secret aws-sm-credentials for External Secrets Operator.
# Reads IAM keys from Secrets Manager (populated by Terraform).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGION="$(terraform -chdir="$ROOT/terraform" output -raw aws_region 2>/dev/null || echo us-east-1)"
SECRET_NAME="$(terraform -chdir="$ROOT/terraform" output -raw eso_credentials_secret_name)"
NAMESPACE="${ESO_NAMESPACE:-external-secrets}"

JSON="$(aws secretsmanager get-secret-value \
  --region "$REGION" \
  --secret-id "$SECRET_NAME" \
  --query SecretString \
  --output text)"

ACCESS_KEY="$(echo "$JSON" | jq -r '.access_key_id')"
SECRET_KEY="$(echo "$JSON" | jq -r '.secret_access_key')"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NAMESPACE" create secret generic aws-sm-credentials \
  --from-literal=access-key-id="$ACCESS_KEY" \
  --from-literal=secret-access-key="$SECRET_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Created/updated secret aws-sm-credentials in namespace $NAMESPACE"
echo "Apply ClusterSecretStore: kubectl apply -f kubernetes/external-secrets/cluster-secret-store.yaml"
