#!/usr/bin/env bash
# Create AWS Secrets Manager entries for n8n and grant ESO IAM read access.
# Usage:
#   ENV=dev  AWS_PROFILE=lla ./bootstrap-n8n-secrets.sh
#   ENVS="stg prod" AWS_PROFILE=lla ./bootstrap-n8n-secrets.sh
set -euo pipefail

PROJECT="${PROJECT:-lla-rke2-cs2}"
ENV="${ENV:-}"
ENVS="${ENVS:-}"
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
  local account_id region policy_doc current n8n_wildcard
  account_id="$(aws sts get-caller-identity --query Account --output text)"
  region="${AWS_REGION}"
  n8n_wildcard="arn:aws:secretsmanager:${region}:${account_id}:secret:${PROJECT}/n8n/*"
  policy_doc="$(aws iam get-user-policy --user-name "$ESO_USER" --policy-name "$ESO_POLICY" --query PolicyDocument --output json)"
  current="$(N8N_WILDCARD="$n8n_wildcard" python3 - <<'PY' "$policy_doc" "${arns[@]}"
import json, os, sys
doc = json.loads(sys.argv[1])
existing = set()
for stmt in doc.get("Statement", []):
    resources = stmt.get("Resource", [])
    if isinstance(resources, str):
        resources = [resources]
    for r in resources:
        existing.add(r)
for arn in sys.argv[2:]:
    existing.add(arn)
existing.add(os.environ["N8N_WILDCARD"])
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
  echo "Updated IAM policy $ESO_POLICY (includes ${n8n_wildcard})"
}

bootstrap_env() {
  local env="$1"
  ENV_SECRET="${PROJECT}/n8n/${env}/env"
  DB_SECRET="${PROJECT}/n8n/${env}/db"

  local enc_key db_user db_pass db_name env_json db_json env_arn db_arn basic_pass
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

  local url
  if [[ "$env" == "prod" ]]; then
    url="https://n8n.lla.internal"
  else
    url="https://n8n-${env}.lla.internal"
  fi

  cat <<EOF

=== n8n ${env} ===
  Secrets: ${ENV_SECRET}, ${DB_SECRET}
  URL:     ${url}
  Basic auth: admin / ${basic_pass}
EOF
}

main() {
  require_aws

  local -a targets=()
  if [[ -n "$ENVS" ]]; then
    read -r -a targets <<<"$ENVS"
  elif [[ -n "$ENV" ]]; then
    targets=("$ENV")
  else
    targets=(dev)
  fi

  for env in "${targets[@]}"; do
    bootstrap_env "$env"
  done

  cat <<EOF

Done. Argo CD apps: $(printf 'lla-cs2-n8n-%s ' "${targets[@]}")
Restart ESO if secrets were added: kubectl -n external-secrets rollout restart deployment external-secrets
EOF
}

main "$@"
