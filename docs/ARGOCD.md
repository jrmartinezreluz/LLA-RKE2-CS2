# Argo CD on LLA-RKE2-CS2

**Argo CD** is the GitOps control plane for this cluster. It is exposed through **Traefik** and **Route53 private DNS** — not through an external NGINX EC2 (CS1 pattern).

---

## Architecture

```text
WireGuard / VPC client
        │
        ▼
Route53  argocd.<internal_domain>
        │
        ▼
Internal NLB :80
        │
        ▼
Traefik (NodePort 30080)
        │
        ▼
argocd-server:80  (server.insecure=true)
```

Default URL: **`http://argocd.lla.internal`** (set `argocd_record_name` / `internal_domain` in Terraform).

---

## Prerequisites

1. RKE2 cluster running (master + 3 workers)
2. **Traefik** installed — [TRAEFIK.md](TRAEFIK.md)
3. `kubectl` with kubeconfig (`https://api.<domain>:6443`)
4. **WireGuard VPN** connected so private Route53 names resolve (`DNS = 10.0.0.2` in client config)

---

## 1. Install Argo CD

From the repository root (use **server-side apply** to avoid CRD annotation size errors):

```bash
kubectl apply --server-side --force-conflicts -k kubernetes/argocd
```

Wait for pods:

```bash
kubectl -n argocd get pods -w
```

All components should become `Running`:

- `argocd-server`
- `argocd-repo-server`
- `argocd-application-controller`
- `argocd-redis`
- `argocd-dex-server` (optional SSO)

---

## 2. Ingress host name

The sample Ingress uses `argocd.lla.internal`. If your Terraform `internal_domain` differs, edit [kubernetes/argocd/ingress.yaml](../kubernetes/argocd/ingress.yaml) before applying:

```yaml
rules:
  - host: argocd.your.internal.domain
```

Terraform also creates a dedicated Route53 record `argocd.<internal_domain>` → ingress NLB.

---

## 3. Web UI access

### Initial admin password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

### Open the UI

With WireGuard (or inside the VPC):

```text
http://argocd.lla.internal
```

- **Username:** `admin`
- **Password:** from the secret above

Terraform output:

```bash
terraform -chdir=terraform output argocd_url
```

---

## 4. Argo CD CLI (optional)

```bash
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd && sudo mv argocd /usr/local/bin/

argocd login argocd.lla.internal --username admin --password <password> --insecure
```

---

## 5. Connect private Git repositories (GitHub App)

Repos privados (`platform-gitops`, `app-charts`) requieren autenticación. Usa **GitHub App** + Secrets Manager + ESO:

**[GITHUB-APP-ARGOCD.md](GITHUB-APP-ARGOCD.md)** — guía paso a paso (recomendado).

Resumen:

```bash
# 1. Crear GitHub App en github.com/settings/apps (ver doc)
# 2. Subir credenciales a AWS
./scripts/setup-argocd-github-app-secret.sh
# 3. Sincronizar en el cluster
kubectl apply -f kubernetes/argocd/external-secret-github-app.yaml
```

---

## 6. Example Application (GitOps)

```bash
argocd app create demo \
  --repo https://github.com/your-org/your-repo.git \
  --path kubernetes \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default \
  --sync-policy automated
```

```bash
argocd app list
argocd app get demo
```

---

## 7. TLS (HTTPS)

See **[TLS.md](TLS.md)** for cert-manager + internal CA + Traefik `websecure`.

Argo CD keeps **`server.insecure: true`**: TLS terminates at Traefik; backend stays HTTP on port 80.

---

## Comparison with CS1

| CS1 | LLA-RKE2-CS2 |
|-----|----------------|
| Argo CD + **Ingress NGINX** | Argo CD + **Traefik** |
| External **NGINX EC2** TLS | **Internal NLB** + Route53 |
| Public FQDN | Private `argocd.<internal_domain>` |

Reference: [AWSK8S-RKE2-CS1/ARGOCD.md](../../AWSK8S-RKE2-CS1/ARGOCD.md)

---

## Deployment order (reminder)

1. Terraform (NLB + Route53 including `argocd` record)
2. Ansible (RKE2)
3. Helm: Traefik
4. `kubectl apply -k kubernetes/argocd`
