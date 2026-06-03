#!/usr/bin/env bash
# Run ON the worker — paste ONE short line at a time if SSH freezes on big blocks.
# Usage on worker: bash bootstrap-erpnext-on-worker-mini.sh
set -euo pipefail
PROJECT="${PROJECT:-lla-rke2-cs2}"
AWS_REGION="${AWS_REGION:-us-east-1}"
ENV="${1:?usage: $0 dev|stg|prod}"

MASTER="$(aws secretsmanager get-secret-value --region "$AWS_REGION" --secret-id "${PROJECT}/erpnext/rds-master" --query SecretString --output text)"
SECRET="$(aws secretsmanager get-secret-value --region "$AWS_REGION" --secret-id "${PROJECT}/erpnext/${ENV}/db" --query SecretString --output text)"
HOST="$(echo "$MASTER" | jq -r .host)"
PORT="$(echo "$MASTER" | jq -r .port)"
ADMIN="$(echo "$MASTER" | jq -r .username)"
export MYSQL_PWD="$(echo "$MASTER" | jq -r .password)"
DB="$(echo "$SECRET" | jq -r .database)"
USER="$(echo "$SECRET" | jq -r .username)"
UPASS="$(echo "$SECRET" | jq -r .password)"

mysql -h "$HOST" -P "$PORT" -u "$ADMIN" -e "
CREATE DATABASE IF NOT EXISTS \`${DB}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${USER}'@'%' IDENTIFIED BY '${UPASS}';
GRANT ALL PRIVILEGES ON \`${DB}\`.* TO '${USER}'@'%';
FLUSH PRIVILEGES;
"
echo "OK ${ENV}: ${DB} / ${USER}"
