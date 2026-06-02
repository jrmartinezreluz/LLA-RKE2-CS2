# ERPNext on LLA-RKE2-CS2

GitOps deployment of ERPNext using Helm charts, Argo CD ApplicationSet, ECR images, and external MariaDB on RDS.

Monitoring (Prometheus/Grafana dashboards) is planned separately.

## Repositories

| Directory / repo | Role |
|------------------|------|
| [app-charts/erpnext](../../app-charts/erpnext/) | Helm wrapper (Frappe + Traefik + ESO + TLS) |
| [platform-gitops](../../platform-gitops/) | Values per env + ApplicationSet |
| [erpnext-app](../../erpnext-app/) | Docker image + GitHub Actions |

## 1. Terraform (RDS + ECR, no backups)

**Always use the canonical directory** (where `terraform.tfstate` for the live cluster lives):

```text
LLA-RKE2-CS2/terraform/     ← plan/apply HERE
LLA-RKE2-CS2-private/terraform/   ← do NOT apply (no real state; duplicate VPC risk)
```

In `LLA-RKE2-CS2/terraform/terraform.tfvars`:

```hcl
enable_erpnext_rds = true
enable_erpnext_ecr = true
```

```bash
cd LLA-RKE2-CS2/terraform
terraform init    # if needed
terraform plan    # should show only ERPNext + ESO policy updates, not 88 resources
terraform apply
terraform output erpnext_ecr_repository_urls
terraform output erpnext_rds_endpoint
terraform output erpnext_db_secret_names
```

RDS is created with `backup_retention_period = 0` and `skip_final_snapshot = true`.

## 2. Bootstrap databases

From a **worker** node (RDS is private; workers have VPC access). After Terraform grants
the node IAM role read access to `erpnext/*` secrets:

```bash
# On worker (SSH), no AWS export needed if IAM was updated:
aws secretsmanager get-secret-value --secret-id lla-rke2-cs2/erpnext/rds-master --region us-east-1

chmod +x /tmp/bootstrap-erpnext-rds-databases.sh
bash /tmp/bootstrap-erpnext-rds-databases.sh
```

**Do not use** `scp` or `ssh ... 'cat > /tmp/file'` from WSL over WireGuard — they often hang and leave a **0-byte file** on the worker.

Preferred (no remote file):

```bash
/ark/LLA-RKE2-CS2/scripts/run-bootstrap-on-worker.sh
```

Or from an **already open** SSH session on the worker, paste/run the script logic directly (see `scripts/bootstrap-erpnext-rds-databases.sh`).

SSH tuning: copy `scripts/ssh-lla.conf.example` into `~/.ssh/config`. Optional: `sudo WG_MTU=1280 ./scripts/wg-up-wsl.sh` if transfers still stall.

Creates `erpnext_dev`, `erpnext_stg`, `erpnext_prod` databases and users matching Secrets Manager entries.

## 3. Push Git repos

Publish to GitHub (replace org/user as needed):

- `app-charts`
- `platform-gitops`
- `erpnext-app`

Update `<AWS_ACCOUNT_ID>` in `platform-gitops/clusters/lla-cs2/erpnext/*.yaml`.

## 4. Argo CD bootstrap

```bash
kubectl apply -f platform-gitops/argocd/projects/apps.yaml
kubectl apply -f platform-gitops/argocd/applicationsets/erpnext.yaml
```

Argo CD creates three Applications: `lla-cs2-erpnext-dev`, `-stg`, `-prod`.

## 5. GitHub Actions OIDC

Terraform creates the IAM role when `enable_erpnext_ecr = true`:

```bash
cd LLA-RKE2-CS2/terraform
terraform apply
./scripts/print-erpnext-github-actions-setup.sh
```

Set secrets on `erpnext-app` (Settings → Secrets → Actions):

| Secret | Value |
|--------|--------|
| `AWS_ROLE_ARN` | `terraform output erpnext_github_actions_role_arn` |
| `GITOPS_PAT` | PAT with write on `platform-gitops` |

Push to `dev` / `stg` / `main` builds `sha-<commit>`, pushes to ECR, updates `platform-gitops`.

If `terraform apply` fails with OIDC provider already exists, set in `terraform.tfvars`:

```hcl
create_github_oidc_provider = false
```

## URLs (WireGuard + internal CA)

| Env | URL |
|-----|-----|
| dev | https://erpnext-dev.lla.internal |
| stg | https://erpnext-stg.lla.internal |
| prod | https://erpnext.lla.internal |

## Second cluster

Add `clusters/lla-cs3/...` values and extend ApplicationSet with a cluster matrix generator — see [platform-gitops README](../../platform-gitops/README.md).

## Troubleshooting

```bash
kubectl -n erpnext-dev get pods,externalsecret,ingress
kubectl -n argocd get applications | grep erpnext
argocd app sync lla-cs2-erpnext-dev   # if CLI configured
```

ExternalSecret must show `SecretSynced` before Frappe site-creation jobs succeed.
