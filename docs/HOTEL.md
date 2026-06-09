# Grand LLA Hotel — blue/green deploy

**Grand LLA Hotel** web app (frontend + backend) for nonprod → prod rollouts. Frontend changes (promotions, seasonal menus) use a **blue/green** strategy on the existing GitOps stack.

## Architecture

```text
                    ┌─────────────────────────────────────┐
                    │  Ingress hotel-dev.lla.internal       │
                    │    /api  → backend (single)           │
                    │    /     → frontend-active Service    │
                    └─────────────────────────────────────┘
                                        │
                    activeSlot=blue ────┼─── selector hotel/slot=blue
                                        │
              ┌─────────────────────────┴─────────────────────────┐
              │                                                     │
     Deployment frontend-blue                              Deployment frontend-green
     image: …-blue (winter theme)                          image: …-green (summer theme)
              ▲                                                     ▲
              │                                                     │
     preview when active=blue                               production when active=green
              │                                                     │
                    ┌─────────────────────────────────────┐
                    │  Ingress hotel-preview-dev.lla.internal │
                    │    /     → frontend-preview Service     │
                    └─────────────────────────────────────┘
```

| URL | Traffic |
|-----|---------|
| https://hotel-dev.lla.internal | **Active** frontend slot + API |
| https://hotel-preview-dev.lla.internal | **Inactive** slot (test before switch) |

Backend is **not** blue/green — only the themed frontend changes, similar to a hotel updating promo pages while the booking API stays stable.

## Repositories

| Repo | Role |
|------|------|
| [hotel-app](https://github.com/jrmartinezreluz/hotel-app) | Source code + **GitHub Actions** (ECR + GitOps) |
| [app-charts/hotel](../../app-charts/hotel/) | Helm chart (2 frontends + router Services) |
| [platform-gitops](../../platform-gitops/) | Values per env + ApplicationSet |

```text
hotel-app  ──push dev/stg/main──►  GitHub Actions
                                        │
                    ┌───────────────────┼───────────────────┐
                    ▼                   ▼                   ▼
                  ECR            platform-gitops      (manual promote)
                    │                   │
                    └─────────┬─────────┘
                              ▼
                         Argo CD → hotel-{dev|stg|prod}
```

## 1. Terraform (ECR + IAM for GitHub Actions)

With `enable_erpnext_ecr = true`, extend `terraform.tfvars`:

```hcl
erpnext_ecr_repositories = [
  "erpnext",
  "hotel-backend",
  "hotel-frontend",
]
```

```bash
cd LLA-RKE2-CS2/terraform
terraform apply
LLA-RKE2-CS2/scripts/print-hotel-github-actions-setup.sh
```

Creates IAM role `lla-rke2-cs2-github-actions-hotel` (OIDC trust on `jrmartinezreluz/hotel-app`).

## 2. GitHub repo `hotel-app`

Push `/ark/hotel-app` to GitHub and set secrets:

| Secret | Value |
|--------|--------|
| `AWS_ROLE_ARN` | `terraform output -raw hotel_github_actions_role_arn` |
| `GITOPS_PAT` | PAT with write on `platform-gitops` |

Branches: `dev`, `stg`, `main` (same model as erpnext-app).

## 3. GitHub Actions workflows

### Deploy (`deploy.yml`) — on push to backend/ or frontend/

1. Reads `blueGreen.activeSlot` from platform-gitops.
2. Builds images for the **inactive** slot (production unchanged):
   - Backend: `sha-<commit>` (if `backend/` changed)
   - Frontend: `sha-<commit>-blue|green` with theme from GitOps
3. Commits tag updates to `platform-gitops`.
4. Argo CD syncs → test **preview** URL.

### Promote (`promote.yml`) — manual

Actions → **Promote blue/green** → pick `dev` / `stg` / `prod`.

Flips `blueGreen.activeSlot` in GitOps → production traffic switches.

## 4. Argo CD bootstrap

```bash
kubectl apply -f platform-gitops/argocd/projects/apps.yaml
kubectl apply -f platform-gitops/argocd/applicationsets/hotel.yaml
```

Application: `lla-cs2-hotel-dev` → namespace `hotel-dev`.

## 5. Verify

```bash
kubectl -n hotel-dev get deploy,svc,ingress
curl -k https://hotel-dev.lla.internal/api/health
curl -k https://hotel-preview-dev.lla.internal/healthz
```

Open both URLs in the browser — active vs preview should show different themes (winter vs summer).

## Blue/green workflow (CI)

**Scenario:** Active is `blue`. You change the summer promo in `frontend/`.

1. `git push origin dev` → Action deploys to **green** (inactive), updates GitOps tags.
2. Open https://hotel-preview-dev.lla.internal — validate menu/promo.
3. Run **Promote blue/green** workflow for `dev`.
4. https://hotel-dev.lla.internal now serves the new green frontend.

Manual alternative: edit `platform-gitops` by hand or use `hotel-app/scripts/build-and-push.sh` locally.

## Blue/green workflow (manual GitOps)

**Scenario:** Active is `blue` (winter). New summer promo frontend `v2-green`.

1. **Deploy to inactive slot** — update only green image tag:

   ```yaml
   frontend:
     slots:
       green:
         image:
           tag: v2-green
   ```

2. Push `platform-gitops` → Argo syncs green Deployment; production still on blue.

3. **Preview** — open https://hotel-preview-dev.lla.internal and validate menu/promo.

4. **Switch traffic** — one field change:

   ```yaml
   blueGreen:
     activeSlot: green
   ```

5. Push → Service `frontend-active` selector flips → users see summer theme instantly.

6. **Next release** — build `v3-blue`, update blue slot tag, preview (now blue is inactive), flip `activeSlot: blue`.

## Local development

```bash
cd hotel-app
docker compose up --build
```

## Environments

| Env | Namespace | Production host | Preview host |
|-----|-----------|-------------------|--------------|
| dev | `hotel-dev` | `hotel-dev.lla.internal` | `hotel-preview-dev.lla.internal` |
| stg | `hotel-stg` | `hotel-stg.lla.internal` | `hotel-preview-stg.lla.internal` |
| prod | `hotel` | `hotel.lla.internal` | `hotel-preview.lla.internal` |

Add `stg.yaml` / `prod.yaml` under `clusters/lla-cs2/hotel/` when ready — the ApplicationSet picks them up automatically.
