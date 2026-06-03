# LLA platform repositories

Complete GitOps stack for **LLA-RKE2-CS2** (RKE2 + Traefik + Argo CD + ERPNext + n8n).

| Repository | Visibility | Role |
|------------|------------|------|
| [LLA-RKE2-CS2](https://github.com/jrmartinezreluz/LLA-RKE2-CS2) | Public | Cluster bootstrap: Terraform, Ansible, Kubernetes platform manifests, scripts |
| [LLA-RKE2-CS2-private](https://github.com/jrmartinezreluz/LLA-RKE2-CS2-private) | **Private** | Same tree + real `tfvars`, inventory, WireGuard configs — sync with `scripts/sync-private-repo.sh` |
| [platform-gitops](https://github.com/jrmartinezreluz/platform-gitops) | Private | Argo CD ApplicationSets, values (`clusters/lla-cs2/{erpnext,n8n}/*.yaml`) |
| [app-charts](https://github.com/jrmartinezreluz/app-charts) | Private | Helm charts (`erpnext/`, `n8n/`) |
| [erpnext-app](https://github.com/jrmartinezreluz/erpnext-app) | Private | Custom ERPNext image, GitHub Actions → ECR → updates platform-gitops image tags |

## Typical clone layout

```bash
git clone git@github.com:jrmartinezreluz/LLA-RKE2-CS2.git
git clone git@github.com:jrmartinezreluz/LLA-RKE2-CS2-private.git
git clone git@github.com:jrmartinezreluz/platform-gitops.git
git clone git@github.com:jrmartinezreluz/app-charts.git
git clone git@github.com:jrmartinezreluz/erpnext-app.git
```

Day-to-day cluster changes: work in **private** ops repo (or sync from public), apply Terraform/Ansible from there; application releases flow through **erpnext-app** → **platform-gitops** → Argo CD.

## Docs (in LLA-RKE2-CS2)

- [ERPNEXT.md](ERPNEXT.md) — RDS, ECR, Argo bootstrap, URLs
- [N8N.md](N8N.md) — n8n dev/stg/prod, bootstrap secrets, URLs
- [ECR-RKE2-CREDENTIAL-PROVIDER.md](ECR-RKE2-CREDENTIAL-PROVIDER.md) — pull images from ECR on nodes
- [CLIENT-VPN.md](CLIENT-VPN.md) — AWS Client VPN (optional; WireGuard also supported)
- [GITHUB-APP-ARGOCD.md](GITHUB-APP-ARGOCD.md) — Argo CD ↔ GitHub App
