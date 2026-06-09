# Prometheus + Grafana + Alertas (kube-prometheus-stack)

Monitoreo completo del cluster RKE2, pods, métricas de aplicaciones y **checks sintéticos** (HTTP/TCP) con **blackbox_exporter**.

---

## Qué incluye

| Componente | Función |
|------------|---------|
| **Prometheus** | Métricas de nodos, API, kubelet, CoreDNS, pods |
| **kube-state-metrics** | Estado de deployments, pods, PVCs, nodos |
| **node-exporter** | CPU, memoria, disco, red por nodo |
| **Grafana** | Dashboards preinstalados + importación vía ConfigMap |
| **Alertmanager** | Enrutamiento de alarmas por severidad (webhook) |
| **blackbox_exporter** | Probes sintéticos HTTPS/TCP a endpoints internos |
| **Reglas custom** | Pods, cluster, sintéticos (`prometheus-rules-custom.yaml`) |

---

## Prerequisites

- RKE2 cluster con workers etiquetados `node-role.kubernetes.io/worker=worker`
- Traefik instalado
- External Secrets Operator + `aws-sm-credentials` (ver [PRODUCTION.md](PRODUCTION.md))
- Contraseña Grafana en Secrets Manager: `lla-rke2-cs2/monitoring/grafana-admin`
- Webhook de alertas en Secrets Manager: `lla-rke2-cs2/monitoring/alertmanager-webhook`
- WireGuard VPN + DNS VPC (`10.0.0.2`)

---

## 1. External Secrets (si no está hecho)

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace \
  -f kubernetes/external-secrets/helm-values.yaml

./scripts/bootstrap-eso-k8s-secret.sh
kubectl apply -f kubernetes/external-secrets/cluster-secret-store.yaml
```

Actualiza `region` en `cluster-secret-store.yaml` si no es `us-east-1`.

---

## 2. Secretos en AWS

```bash
# Grafana admin
aws secretsmanager put-secret-value \
  --secret-id lla-rke2-cs2/monitoring/grafana-admin \
  --secret-string "$(openssl rand -base64 24)"

# Webhook de alertas (Slack, Discord, PagerDuty, etc.)
aws secretsmanager put-secret-value \
  --secret-id lla-rke2-cs2/monitoring/alertmanager-webhook \
  --secret-string 'https://hooks.slack.com/services/T000/B000/XXXX'
```

Si el secret `alertmanager-webhook` no existe aún, créalo con Terraform (`terraform apply` en `terraform/`) o manualmente en AWS Console.

---

## 3. Instalación completa (recomendado)

```bash
chmod +x scripts/install-monitoring.sh
./scripts/install-monitoring.sh
```

O paso a paso:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

kubectl create namespace monitoring

kubectl apply -f kubernetes/monitoring/external-secret-grafana.yaml
kubectl apply -f kubernetes/monitoring/external-secret-alertmanager.yaml

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f kubernetes/monitoring/helm-values.yaml

helm upgrade --install prometheus-blackbox-exporter prometheus-community/prometheus-blackbox-exporter \
  -n monitoring \
  -f kubernetes/monitoring/blackbox-exporter/helm-values.yaml

kubectl apply -f kubernetes/monitoring/probes.yaml
kubectl apply -f kubernetes/monitoring/prometheus-rules-custom.yaml
kubectl apply -f kubernetes/monitoring/alertmanager-config.yaml
kubectl apply -f kubernetes/monitoring/ingress-grafana.yaml
```

Esperar pods:

```bash
kubectl -n monitoring get pods -w
```

---

## 4. Grafana

Edita el host en `kubernetes/monitoring/ingress-grafana.yaml` si `internal_domain` difiere.

Abre: **`https://grafana.lla.internal`**

- **User:** `admin`
- **Password:** valor en Secrets Manager (`grafana-admin`)

---

## 4.1 Ver todo en Grafana (sin port-forward)

**URL:** https://grafana.lla.internal — ahí ves cluster, pods y sintéticos.

### Carpeta **LLA Monitoring**

| Dashboard | Qué muestra |
|-----------|-------------|
| **LLA - Cluster & Synthetics Overview** | Nodos, pods, sintéticos OK/FAIL, CPU/mem por namespace |

### Dashboards del chart (carpeta **General** o **Kubernetes**)

| Dashboard | Qué muestra |
|-----------|-------------|
| **Kubernetes / Compute Resources / Cluster** | CPU, memoria, red del cluster |
| **Kubernetes / Compute Resources / Namespace (Pods)** | Recursos por namespace |
| **Kubernetes / Compute Resources / Pod** | CPU/mem por pod (elige namespace arriba) |
| **Kubernetes / Kubelet** | Métricas kubelet |
| **Node Exporter / Nodes** | CPU, disco, red por nodo |
| **Prometheus / Overview** | Estado de Prometheus |
| **Blackbox Exporter - Synthetics** | Detalle probes HTTP/TCP por app |

### Sintéticos (aplicativos)

En **LLA Overview** o **Explore** → query `probe_success`:

| Endpoint | App |
|----------|-----|
| `grafana.lla.internal` | Plataforma |
| `argocd.lla.internal` | Plataforma |
| `api.lla.internal:6443` | API K8s |
| `hotel-dev.lla.internal/api/health` | Hotel API |
| `hotel-dev.lla.internal/healthz` | Hotel frontend |
| `n8n-dev.lla.internal/healthz` | n8n |
| `erpnext-dev.lla.internal` | ERPNext |

`probe_success = 1` → OK · `0` → caído

### Aplicar dashboards nuevos

```bash
helm upgrade monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring -f kubernetes/monitoring/helm-values.yaml

kubectl apply -f kubernetes/monitoring/grafana-dashboards/
kubectl apply -f kubernetes/monitoring/probes.yaml
```

Los dashboards aparecen en ~1 min (sidecar de Grafana).

---

## 5. Monitoreo de pods

### Métricas automáticas (sin configuración)

- **cAdvisor/kubelet:** CPU, memoria, red por contenedor
- **kube-state-metrics:** fase del pod, restarts, readiness, réplicas de deployment
- **Reglas de alerta:** `PodCrashLooping`, `PodNotReady`, `PodHighRestartRate`, `DeploymentReplicasMismatch`

### Métricas Prometheus de aplicaciones

Añade anotaciones al pod/deployment:

```yaml
metadata:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/metrics"
```

Prometheus descubre automáticamente pods con `prometheus.io/scrape=true` en **todos los namespaces**.

Alternativa: crea un `ServiceMonitor` o `PodMonitor` en el namespace de la app (también descubierto automáticamente).

---

## 6. Checks sintéticos (blackbox)

Archivo: `kubernetes/monitoring/probes.yaml`

Probes activos por defecto:

| Target | Tipo | Descripción |
|--------|------|-------------|
| `https://grafana.lla.internal/` | HTTPS | UI Grafana |
| `https://argocd.lla.internal/` | HTTPS | UI Argo CD |
| `api.lla.internal:6443` | TCP | API Kubernetes |

Descomenta la sección `apps-https` para hotel, n8n, etc.

Alarmas relacionadas:

- **BlackboxProbeFailed** (critical) — probe caído > 2 min
- **BlackboxProbeSlow** (warning) — respuesta > 5 s
- **BlackboxSslCertExpiringSoon** (warning) — cert expira en < 14 días

Verificar en Prometheus → Status → Targets (job `blackbox-*`).

---

## 7. Alarmas

### Reglas incluidas

**Sintéticos:** `BlackboxProbeFailed`, `BlackboxProbeSlow`, `BlackboxSslCertExpiringSoon`

**Pods:** `PodNotReady`, `PodCrashLooping`, `PodHighRestartRate`, `DeploymentReplicasMismatch`

**Cluster:** `NodeNotReady`, `NodeMemoryPressure`, `NodeDiskPressure`, `PersistentVolumeFillingUp`

**Default (kube-prometheus-stack):** reglas adicionales de API, kubelet, Prometheus, etc.

### Alertmanager

Configuración: `kubernetes/monitoring/alertmanager-config.yaml`

- Severidad **critical** y **warning** → webhook desde Secrets Manager
- `Watchdog` e `InfoInhibitor` silenciados (heartbeat interno)

Probar una alerta:

```bash
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-alertmanager 9093:9093
# Abrir http://127.0.0.1:9093 → crear silencio o ver alertas activas
```

---

## 8. Prometheus UI (opcional)

Port-forward (VPN):

```bash
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090
```

Browse `http://127.0.0.1:9090`

Consultas útiles:

```promql
# Pods no ready
kube_pod_status_ready{condition="true"} == 0

# Probes sintéticos
probe_success

# Restarts por pod (1h)
increase(kube_pod_container_status_restarts_total[1h])
```

---

## Storage

PVCs usan storage class **local-path** de RKE2. Asegura capacidad en workers (`root_volume_size_gb` en Terraform).

---

## Security groups

Workers permiten **TCP 9100** desde master y CIDR VPC para scrapes de node-exporter.

---

## Personalizar

| Parámetro | Archivo |
|-----------|---------|
| Retención Prometheus | `helm-values.yaml` → `prometheus.prometheusSpec.retention` |
| Endpoints sintéticos | `probes.yaml` |
| Reglas de alerta | `prometheus-rules-custom.yaml` |
| Receptor de alertas | `alertmanager-config.yaml` + secret AWS |
| Dashboards | Grafana UI o ConfigMaps con label `grafana_dashboard: "1"` |

---

## Upgrade

```bash
./scripts/install-monitoring.sh
```

O solo el stack principal:

```bash
helm upgrade monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring -f kubernetes/monitoring/helm-values.yaml
```
