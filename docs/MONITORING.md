# Prometheus + Grafana (kube-prometheus-stack)

Production-style monitoring for LLA-RKE2-CS2 using the **kube-prometheus-stack** Helm chart.

---

## Prerequisites

- RKE2 cluster with workers labeled `node-role.kubernetes.io/worker=worker`
- Traefik installed
- External Secrets Operator + `aws-sm-credentials` (see [PRODUCTION.md](PRODUCTION.md))
- Grafana admin password set in Secrets Manager: `lla-rke2-cs2/monitoring/grafana-admin`
- WireGuard VPN + VPC DNS (`10.0.0.2`)

---

## 1. External Secrets (if not done)

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace \
  -f kubernetes/external-secrets/helm-values.yaml

./scripts/bootstrap-eso-k8s-secret.sh
kubectl apply -f kubernetes/external-secrets/cluster-secret-store.yaml
```

Update `region` in `cluster-secret-store.yaml` if not `us-east-1`.

---

## 2. Set Grafana password in AWS

```bash
aws secretsmanager put-secret-value \
  --secret-id lla-rke2-cs2/monitoring/grafana-admin \
  --secret-string "$(openssl rand -base64 24)"
```

---

## 3. Install kube-prometheus-stack

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

kubectl create namespace monitoring

kubectl apply -f kubernetes/monitoring/external-secret-grafana.yaml

helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f kubernetes/monitoring/helm-values.yaml
```

Wait for pods:

```bash
kubectl -n monitoring get pods -w
```

---

## 4. Expose Grafana via Traefik

Edit host in `kubernetes/monitoring/ingress-grafana.yaml` if `internal_domain` differs, then:

```bash
kubectl apply -f kubernetes/monitoring/ingress-grafana.yaml
```

Open: **`http://grafana.lla.internal`** (or `terraform output grafana_url`)

- **User:** `admin`
- **Password:** value in Secrets Manager (`grafana-admin`)

---

## 5. Prometheus UI (optional)

Port-forward (VPN):

```bash
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090
```

Browse `http://127.0.0.1:9090`

---

## Storage

PVCs use RKE2 **local-path** storage class. Ensure workers have disk capacity (`root_volume_size_gb` in Terraform).

---

## Security groups

Workers allow **TCP 9100** from master and VPC CIDR for node-exporter scrapes.

---

## Customize

- Retention: `prometheus.prometheusSpec.retention` in `helm-values.yaml`
- Alerts: configure `alertmanager` receivers for your team
- Dashboards: import via Grafana UI or ConfigMaps
