# TLS for internal apps (`*.lla.internal`)

Private Route53 zone — use **cert-manager** with an **internal CA**, not Let's Encrypt.

Traffic path:

```text
https://argocd.lla.internal
  → ingress NLB :443
  → Traefik NodePort 30443 (TLS terminate)
  → Service ClusterIP :80 (HTTP)
```

Argo CD keeps `server.insecure: true` (TLS only at Traefik edge).

---

See also [SECURITY-PUBLIC-REPO.md](SECURITY-PUBLIC-REPO.md) before publishing this repository.

## 1. Install cert-manager

From WSL (VPN + `KUBECONFIG`):

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm upgrade --install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace \
  --set installCRDs=true \
  -f kubernetes/cert-manager/helm-values.yaml

kubectl -n cert-manager wait --for=condition=Available deployment/cert-manager --timeout=180s
kubectl -n cert-manager wait --for=condition=Available deployment/cert-manager-webhook --timeout=180s
```

## 2. Create internal CA + wildcard certificate

```bash
kubectl apply -f kubernetes/cert-manager/lla-ca.yaml
kubectl wait --for=condition=Ready certificate/lla-internal-ca -n cert-manager --timeout=120s

kubectl apply -f kubernetes/cert-manager/certificate-wildcard.yaml
kubectl apply -f kubernetes/cert-manager/certificate-wildcard-argocd.yaml
kubectl apply -f kubernetes/cert-manager/certificate-wildcard-monitoring.yaml
kubectl wait --for=condition=Ready certificate/lla-internal-wildcard -n traefik --timeout=120s
kubectl wait --for=condition=Ready certificate/lla-internal-wildcard -n argocd --timeout=120s
kubectl wait --for=condition=Ready certificate/lla-internal-wildcard -n monitoring --timeout=120s
```

## 3. Upgrade Traefik (HTTPS + HTTP redirect)

```bash
helm repo add traefik https://traefik.github.io/charts
helm upgrade traefik traefik/traefik -n traefik \
  -f kubernetes/traefik/helm-values.yaml
```

## 4. Apply Ingress (websecure)

```bash
kubectl apply -f kubernetes/argocd/ingress.yaml          # namespace: argocd
kubectl apply -f kubernetes/monitoring/ingress-grafana.yaml
```

Or Argo CD via kustomize: `kubectl apply --server-side --force-conflicts -k kubernetes/argocd` (includes ingress).

## 5. Trust the CA on your laptop (required for browsers)

Export CA from the cluster:

```bash
kubectl -n cert-manager get secret lla-internal-ca-secret \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > lla-internal-ca.crt
```

**Windows:** double-click `lla-internal-ca.crt` → Install → **Local Machine** or **Current User** → **Trusted Root Certification Authorities**.

**WSL/Linux:**

```bash
sudo cp lla-internal-ca.crt /usr/local/share/ca-certificates/lla-internal.crt
sudo update-ca-certificates
```

## 6. Verify

```bash
curl -v https://argocd.lla.internal/
curl -v https://grafana.lla.internal/
```

Browser: `https://argocd.lla.internal`, `https://grafana.lla.internal` (no port).

---

## New applications

1. Create `Ingress` with `host: myapp.lla.internal`.
2. Annotation `traefik.ingress.kubernetes.io/router.entrypoints: websecure`.
3. Wildcard cert covers `*.lla.internal` via Traefik default certificate (no extra cert per app).

Optional explicit TLS on Ingress (secret must be in the **same namespace** as the Ingress):

```yaml
spec:
  tls:
    - hosts:
        - myapp.lla.internal
      secretName: myapp-tls
```

Use a `Certificate` in that namespace, or rely on the Traefik default wildcard.

---

## URLs

| Service | URL |
|---------|-----|
| Argo CD | `https://argocd.lla.internal` |
| Grafana | `https://grafana.lla.internal` |
| API | `https://api.lla.internal:6443` (RKE2 cert, separate) |

Update `ansible/group_vars/all.yml` `argocd_url` / `grafana_url` to `https://` after cutover.
