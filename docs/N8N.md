# n8n on LLA-RKE2-CS2

GitOps deployment via **app-charts/n8n** and **platform-gitops** ApplicationSet `n8n`.

## URLs

| Env | URL |
|-----|-----|
| dev | https://n8n-dev.lla.internal |

## 1. Bootstrap AWS secrets (once per env)

Requires AWS SSO (`aws sso login --profile lla`):

```bash
chmod +x LLA-RKE2-CS2/scripts/bootstrap-n8n-secrets.sh
AWS_PROFILE=lla LLA-RKE2-CS2/scripts/bootstrap-n8n-secrets.sh
```

Creates in Secrets Manager:

- `lla-rke2-cs2/n8n/dev/env` — `N8N_ENCRYPTION_KEY`, optional basic auth
- `lla-rke2-cs2/n8n/dev/db` — Postgres credentials for in-cluster DB

Updates IAM user `lla-rke2-cs2-external-secrets` to read the new secret ARNs.

## 2. Argo CD ApplicationSet

```bash
kubectl apply -f platform-gitops/argocd/projects/apps.yaml
kubectl apply -f platform-gitops/argocd/applicationsets/n8n.yaml
```

Application: `lla-cs2-n8n-dev` → namespace `n8n-dev`.

## 3. Verify

```bash
kubectl -n n8n-dev get pods,externalsecret,ingress
curl -k -u admin:<password> https://n8n-dev.lla.internal/healthz
```

Basic auth password is printed once by the bootstrap script.

## Architecture (dev)

- **n8n** + **in-cluster PostgreSQL 16** (PVC `local-path`, `Recreate` strategy)
- **Traefik** ingress + **cert-manager** wildcard `*.lla.internal`
- **External Secrets** → AWS Secrets Manager

For stg/prod, disable `postgresql.enabled` in values and point `externalDatabase` at RDS PostgreSQL (Terraform extension — same pattern as ERPNext RDS).

## Repos

| Repo | Path |
|------|------|
| app-charts | `n8n/` |
| platform-gitops | `clusters/lla-cs2/n8n/dev.yaml`, `argocd/applicationsets/n8n.yaml |

See also [docs/REPOS.md](REPOS.md).
