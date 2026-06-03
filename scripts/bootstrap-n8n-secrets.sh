#!/usr/bin/env bash
# Create AWS Secrets Manager entries for n8n (dev) and grant ESO IAM read access.
set -euo pipefail

PROJECT="${PROJECT:-lla-rke2-cs2}"
ENV="${ENV:-dev}"
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_PROFILE="${AWS_PROFILE:-default}"
ESO_USER="${ESO_USER:-${PROJECT}-external-secrets}"
ESO_POLICY="${ESO_POLICY:-${PROJECT}-external-secrets-read}"

ENV_SECRET="${PROJECT}/n8n/${ENV}/env"
DB_SECRET="${PROJECT}/n8n/${ENV}/db"

require_aws() {
  if ! aws sts get-caller-identity &>/dev/null; then
    echo "Configure AWS credentials first (e.g. aws sso login --profile \$AWS_PROFILE)" >&2
    exit 1
  fi
}

rand_hex() {
  openssl rand -hex 32
}

rand_pass() {
  openssl rand -base64 24 | tr -d '/+=' | head -c 24
}

upsert_secret() {
  local name="$1"
  local payload="$2"
  if aws secretsmanager describe-secret --secret-id "$name" &>/dev/null; then
    echo "Updating secret $name"
    aws secretsmanager put-secret-value --secret-id "$name" --secret-string "$payload" >/dev/null
  else
    echo "Creating secret $name"
    aws secretsmanager create-secret --name "$name" --secret-string "$payload" >/dev/null
  fi
  aws secretsmanager describe-secret --secret-id "$name" --query ARN --output text
}

grant_eso_access() {
  local -a arns=("$@")
  local policy_doc current
  policy_doc="$(aws iam get-user-policy --user-name "$ESO_USER" --policy-name "$ESO_POLICY" --query PolicyDocument --output json)"
  current="$(python3 - <<'PY' "$policy_doc" "${arns[@]}"
import json, sys
doc = json.loads(sys.argv[1])
existing = set()
for stmt in doc.get("Statement", []):
    for r in stmt.get("Resource", []):
        existing.add(r)
for arn in sys.argv[2:]:
    existing.add(arn)
doc["Statement"] = [{
    "Sid": "ReadProjectSecrets",
    "Effect": "Allow",
    "Action": ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"],
    "Resource": sorted(existing),
}]
print(json.dumps(doc))
PY
)"
  aws iam put-user-policy \
    --user-name "$ESO_USER" \
    --policy-name "$ESO_POLICY" \
    --policy-document "$current" >/dev/null
  echo "Updated IAM policy $ESO_POLICY on user $ESO_USER"
}

main() {
  require_aws

  local enc_key db_user db_pass db_name env_json db_json env_arn db_arn
  enc_key="$(rand_hex)"
  db_user="n8n"
  db_pass="$(rand_pass)"
  db_name="n8n"
  basic_pass="$(rand_pass)"

  env_json="$(jq -n \
    --arg k "$enc_key" \
    --arg u "admin" \
    --arg p "$basic_pass" \
    '{N8N_ENCRYPTION_KEY: $k, N8N_BASIC_AUTH_ACTIVE: "true", N8N_BASIC_AUTH_USER: $u, N8N_BASIC_AUTH_PASSWORD: $p}')"

  db_json="$(jq -n \
    --arg u "$db_user" \
    --arg p "$db_pass" \
    --arg d "$db_name" \
    '{username: $u, password: $p, database: $d, host: "n8n-postgres", port: "5432"}')"

  env_arn="$(upsert_secret "$ENV_SECRET" "$env_json")"
  db_arn="$(upsert_secret "$DB_SECRET" "$db_json")"

  grant_eso_access "$env_arn" "$db_arn"

  cat <<EOF

n8n secrets ready for environment: ${ENV}

  ${ENV_SECRET}
  ${DB_SECRET}

Basic auth (optional layer in front of n8n UI):
  user:  admin
  pass:  ${basic_pass}

Next:
  kubectl apply -f platform-gitops/argocd/applicationsets/n8n.yaml
  # Argo CD syncs lla-cs2-n8n-${ENV} -> https://n8n-${ENV}.lla.internal

Store the basic auth password in your password manager; it is not printed again.
EOF
}

main "$@"
