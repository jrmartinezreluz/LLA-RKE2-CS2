# n8n on LLA-RKE2-CS2

GitOps deployment via **app-charts/n8n** and **platform-gitops** ApplicationSet `n8n`.

## URLs

| Env | URL | Namespace |
|-----|-----|-----------|
| dev | https://n8n-dev.lla.internal | `n8n-dev` |
| stg | https://n8n-stg.lla.internal | `n8n-stg` |
| prod | https://n8n.lla.internal | `n8n` |

## 1. Bootstrap AWS secrets (once per env)

Requires AWS SSO (`aws sso login --profile lla`):

```bash
chmod +x LLA-RKE2-CS2/scripts/bootstrap-n8n-secrets.sh
# All environments:
AWS_PROFILE=lla ENVS="dev stg prod" LLA-RKE2-CS2/scripts/bootstrap-n8n-secrets.sh
# Or one at a time:
AWS_PROFILE=lla ENV=stg LLA-RKE2-CS2/scripts/bootstrap-n8n-secrets.sh
```

Creates per env in Secrets Manager:

- `lla-rke2-cs2/n8n/{env}/env` — `N8N_ENCRYPTION_KEY`, basic auth
- `lla-rke2-cs2/n8n/{env}/db` — Postgres credentials for in-cluster DB

IAM wildcard `lla-rke2-cs2/n8n/*` covers all environments.

## 2. Argo CD ApplicationSet

```bash
kubectl apply -f platform-gitops/argocd/projects/apps.yaml
kubectl apply -f platform-gitops/argocd/applicationsets/n8n.yaml
```

Applications: `lla-cs2-n8n-dev`, `lla-cs2-n8n-stg`, `lla-cs2-n8n-prod`.

## 3. Verify

```bash
kubectl -n n8n-dev get pods,externalsecret,ingress
curl -k -u admin:<password> https://n8n-dev.lla.internal/healthz
```

Basic auth password is printed once by the bootstrap script.

## Architecture

- **n8n** + **in-cluster PostgreSQL 16** per namespace (PVC `local-path`, `Recreate`)
- **Traefik** + **cert-manager** wildcard `*.lla.internal`
- **External Secrets** → AWS Secrets Manager (`lla-rke2-cs2/n8n/{env}/*`)

## Repos

| Repo | Path |
|------|------|
| app-charts | `n8n/` |
| platform-gitops | `clusters/lla-cs2/n8n/{dev,stg,prod}.yaml` |

See also [docs/REPOS.md](REPOS.md).
