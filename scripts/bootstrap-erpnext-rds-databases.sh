#!/usr/bin/env bash
# Create ERPNext databases/users on the shared RDS instance.
# Run from a host with WireGuard + mysql client (e.g. WireGuard EC2).
set -euo pipefail

PROJECT="${PROJECT:-lla-rke2-cs2}"
AWS_REGION="${AWS_REGION:-us-east-1}"
ENVIRONMENTS="${ENVIRONMENTS:-dev stg prod}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require aws
require mysql
require jq

echo "Fetching RDS master credentials from Secrets Manager..."
MASTER_JSON="$(aws secretsmanager get-secret-value \
  --region "$AWS_REGION" \
  --secret-id "${PROJECT}/erpnext/rds-master" \
  --query SecretString --output text)"

HOST="$(echo "$MASTER_JSON" | jq -r .host)"
PORT="$(echo "$MASTER_JSON" | jq -r .port)"
ADMIN_USER="$(echo "$MASTER_JSON" | jq -r .username)"
ADMIN_PASS="$(echo "$MASTER_JSON" | jq -r .password)"

export MYSQL_PWD="$ADMIN_PASS"

for env in $ENVIRONMENTS; do
  echo "Provisioning environment: $env"
  SECRET_JSON="$(aws secretsmanager get-secret-value \
    --region "$AWS_REGION" \
    --secret-id "${PROJECT}/erpnext/${env}/db" \
    --query SecretString --output text)"

  DB="$(echo "$SECRET_JSON" | jq -r .database)"
  USER="$(echo "$SECRET_JSON" | jq -r .username)"
  PASS="$(echo "$SECRET_JSON" | jq -r .password)"

  mysql -h "$HOST" -P "$PORT" -u "$ADMIN_USER" <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${USER}'@'%' IDENTIFIED BY '${PASS}';
GRANT ALL PRIVILEGES ON \`${DB}\`.* TO '${USER}'@'%';
FLUSH PRIVILEGES;
SQL

  echo "  OK: database=${DB} user=${USER}"
done

echo "Done. ERPNext Helm jobs can now connect using ESO secrets lla-rke2-cs2/erpnext/{env}/db"
