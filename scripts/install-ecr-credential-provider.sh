#!/usr/bin/env bash
# Install Amazon ECR kubelet credential provider on RKE2 nodes (uses instance IAM role).
# RKE2 reads defaults: /var/lib/rancher/credentialprovider/{bin,config.yaml}
set -euo pipefail

BIN_DIR="/var/lib/rancher/credentialprovider/bin"
CONFIG_FILE="/var/lib/rancher/credentialprovider/config.yaml"
BINARY_NAME="ecr-credential-provider"
S3_BUCKET="amazon-eks"
S3_REGION="${S3_REGION:-us-west-2}"
FALLBACK_URL="https://${S3_BUCKET}.s3.${S3_REGION}.amazonaws.com/1.30.0/2024-05-12/bin/linux/amd64/ecr-credential-provider"

discover_download_url() {
  if ! command -v aws >/dev/null 2>&1; then
    echo "$FALLBACK_URL"
    return
  fi
  local key
  for minor in 1.35 1.34 1.33 1.32 1.31 1.30; do
    key="$(aws s3api list-objects-v2 --bucket "$S3_BUCKET" --prefix "${minor}" \
      --query "Contents[?ends_with(Key, 'bin/linux/amd64/${BINARY_NAME}')].Key" \
      --output text 2>/dev/null | tr '\t' '\n' | sort -V | tail -1 || true)"
    if [[ -n "$key" && "$key" != "None" ]]; then
      echo "https://${S3_BUCKET}.s3.${S3_REGION}.amazonaws.com/${key}"
      return
    fi
  done
  echo "$FALLBACK_URL"
}

install_on_host() {
  local url
  url="$(discover_download_url)"
  echo "Using ECR credential provider binary: $url"

  sudo mkdir -p "$BIN_DIR"
  sudo curl -fsSL -o "${BIN_DIR}/${BINARY_NAME}" "$url"
  sudo chmod 755 "${BIN_DIR}/${BINARY_NAME}"

  sudo tee "$CONFIG_FILE" >/dev/null <<'EOF'
apiVersion: kubelet.config.k8s.io/v1
kind: CredentialProviderConfig
providers:
  - name: ecr-credential-provider
    matchImages:
      - "*.dkr.ecr.*.amazonaws.com"
      - "*.dkr.ecr.*.amazonaws.com.cn"
      - "*.dkr.ecr-fips.*.amazonaws.com"
    defaultCacheDuration: 12h
    apiVersion: credentialprovider.kubelet.k8s.io/v1
EOF
  sudo chmod 644 "$CONFIG_FILE"

  if systemctl is-active --quiet rke2-agent.service 2>/dev/null; then
    echo "Restarting rke2-agent..."
    sudo systemctl restart rke2-agent.service
  fi
  if systemctl is-active --quiet rke2-server.service 2>/dev/null; then
    echo "Restarting rke2-server..."
    sudo systemctl restart rke2-server.service
  fi

  ls -la "$BIN_DIR" "$CONFIG_FILE"
}

install_on_host "$@"
