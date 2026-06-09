#!/usr/bin/env bash
# Install or upgrade full monitoring stack: kube-prometheus-stack, blackbox exporter,
# synthetics, custom alerts, and Alertmanager webhook routing.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"
KUBECTL_LLA="$ROOT/scripts/kubectl-lla.sh"

if [[ -n "${KUBECTL_CMD:-}" ]]; then
  KUBECTL=("$KUBECTL_CMD")
elif [[ -x "$KUBECTL_LLA" ]]; then
  KUBECTL=("$KUBECTL_LLA")
elif command -v kubectl >/dev/null 2>&1; then
  echo "WARN: $KUBECTL_LLA not found; using local kubectl (may hang over WSL+VPN)" >&2
  KUBECTL=(kubectl)
else
  echo "ERROR: neither $KUBECTL_LLA nor kubectl found in PATH" >&2
  exit 1
fi

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update prometheus-community

"${KUBECTL[@]}" create namespace "$NAMESPACE" --dry-run=client -o yaml | "${KUBECTL[@]}" apply -f -

echo "==> External Secrets (Grafana + Alertmanager webhook)"
"${KUBECTL[@]}" apply -f "$ROOT/kubernetes/monitoring/external-secret-grafana.yaml"
"${KUBECTL[@]}" apply -f "$ROOT/kubernetes/monitoring/external-secret-alertmanager.yaml"

echo "==> kube-prometheus-stack"
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -n "$NAMESPACE" \
  -f "$ROOT/kubernetes/monitoring/helm-values.yaml" \
  --wait --timeout 10m

echo "==> prometheus-blackbox-exporter (synthetics)"
helm upgrade --install prometheus-blackbox-exporter prometheus-community/prometheus-blackbox-exporter \
  -n "$NAMESPACE" \
  -f "$ROOT/kubernetes/monitoring/blackbox-exporter/helm-values.yaml" \
  --wait --timeout 5m

echo "==> Probes, custom rules, Alertmanager routing"
"${KUBECTL[@]}" apply -f "$ROOT/kubernetes/monitoring/probes.yaml"
"${KUBECTL[@]}" apply -f "$ROOT/kubernetes/monitoring/prometheus-rules-custom.yaml"
"${KUBECTL[@]}" apply -f "$ROOT/kubernetes/monitoring/alertmanager-config.yaml"

echo "==> Grafana dashboards (LLA overview + blackbox)"
"${KUBECTL[@]}" apply -f "$ROOT/kubernetes/monitoring/grafana-dashboards/lla-overview.yaml"
"${KUBECTL[@]}" apply -f "$ROOT/kubernetes/monitoring/grafana-dashboards/blackbox-exporter.yaml"

echo "==> Grafana ingress (Traefik)"
"${KUBECTL[@]}" apply -f "$ROOT/kubernetes/monitoring/ingress-grafana.yaml"

echo ""
echo "Monitoring stack installed in namespace: $NAMESPACE"
"${KUBECTL[@]}" -n "$NAMESPACE" get pods
echo ""
echo "Next steps:"
echo "  1. Set Grafana password:  aws secretsmanager put-secret-value --secret-id lla-rke2-cs2/monitoring/grafana-admin --secret-string \"\$(openssl rand -base64 24)\""
echo "  2. Set alert webhook URL: aws secretsmanager put-secret-value --secret-id lla-rke2-cs2/monitoring/alertmanager-webhook --secret-string 'https://hooks.slack.com/services/...'"
echo "  3. Open Grafana: https://grafana.lla.internal (admin / Secrets Manager password)"
echo "  4. Edit probes: kubernetes/monitoring/probes.yaml (uncomment app endpoints)"
