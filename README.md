# LLA-RKE2-CS2

**Client:** LLA | **Author:** José Martinez | Arkhadia by GHC

**Nonprod environment operated with production posture** — single-AZ VPC, private **RKE2** (1 master, 3 workers), **WireGuard-only** access, **AWS Secrets Manager**, **Prometheus + Grafana**. No backups in scope.

| Layer | Technology |
|-------|------------|
| Ingress | **Traefik** (Helm) |
| Load balancing | **AWS internal NLB** + Route53 private DNS |
| GitOps | **Argo CD** (`kubernetes/argocd/`) |
| Monitoring | **kube-prometheus-stack** (Prometheus + Grafana) |
| Secrets | **AWS Secrets Manager** + **External Secrets Operator** |
| Hardening | Split SGs, EBS encryption, IMDSv2, RKE2 secrets encryption — [PRODUCTION.md](docs/PRODUCTION.md) |

Patterns reference only: [AWSK8S-RKE2-CS1](../AWSK8S-RKE2-CS1).

**Repositories:** this public repo is a sanitized reference. Deployment-specific files (`all.yml`, inventory, `tfvars`, WireGuard configs) belong in a **private** ops repo — see [docs/PRIVATE-REPO.md](docs/PRIVATE-REPO.md). Full stack map: [docs/REPOS.md](docs/REPOS.md).

---

## Architecture

| Component | Count |
|-----------|-------|
| WireGuard | 1 (public) — sole SSH/VPN entry |
| Internal NLB (API/join) | 1 → master1 |
| Internal NLB (ingress) | 1 → workers (Traefik NodePorts) |
| Route53 private zone | `api`, `join`, `ingress`, `argocd`, `grafana`, `*.lla.internal` |
| Argo CD | `http://argocd.lla.internal` |
| Grafana | `http://grafana.lla.internal` |
| RKE2 master | 1 (private) |
| RKE2 workers | 3 (private) |

**[docs/PRODUCTION.md](docs/PRODUCTION.md)** · **[docs/architecture.md](docs/architecture.md)** · **[docs/MONITORING.md](docs/MONITORING.md)** · **[docs/ARGOCD.md](docs/ARGOCD.md)**

---

## Repository layout

```
LLA-RKE2-CS2/
├── docs/
│   ├── architecture.md
│   ├── DNS-AND-LOAD-BALANCERS.md
│   └── TRAEFIK.md
├── kubernetes/
│   ├── traefik/
│   ├── argocd/
│   ├── monitoring/         # Prometheus + Grafana
│   └── external-secrets/
├── terraform/              # VPC, EC2, IAM, Secrets Manager, NLB, Route53
├── ansible/
├── scripts/
│   ├── sync-ansible-vars.sh
│   └── bootstrap-eso-k8s-secret.sh
└── requirements.txt
```

---

## Prerequisites

- AWS account, CLI credentials, EC2 key pair in target region
- Terraform >= 1.5
- Ansible >= 8, `jq`
- SSH private key matching the EC2 key pair

---

## 1. Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit: key_name, ssh_ingress_cidr, wireguard_ingress_cidr, internal_domain
# Recommended for roaming: keep SSH /32, set wireguard_ingress_cidr = 0.0.0.0/0

terraform init
terraform plan
terraform apply
```

Capture outputs:

```bash
terraform output wireguard_public_ip
terraform output master_private_ip
terraform output worker_private_ips
terraform output kubernetes_api_url
terraform output api_fqdn
terraform output ingress_fqdn
terraform output argocd_url
```

---

## 2. Ansible variables and inventory

```bash
cd ..
chmod +x scripts/sync-ansible-vars.sh
./scripts/sync-ansible-vars.sh

cd ansible
cp inventory.ini.example inventory.ini
cp group_vars/all.yml.example group_vars/all.yml
```

Edit `inventory.ini` with IPs from Terraform. Set `ansible_ssh_private_key_file` in `group_vars/all.yml`.

---

## 3. Bootstrap cluster (WireGuard only)

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r ../requirements.txt

# Phase 1: WireGuard server (SSH to public IP — no VPN yet)
ansible-playbook site.yml
```

Configure your **WireGuard client** (peer + `DNS = 10.0.0.2`). See [docs/architecture.md](docs/architecture.md). Connect the VPN, then:

```bash
# Phase 2: RKE2 (private IPs — VPN must be up)
ansible-playbook playbooks/playbook-master1.yml
```

```bash
export RKE2_CLUSTER_TOKEN="$(ssh ubuntu@$(cd ../terraform && terraform output -raw master_private_ip) \
  'sudo cat /var/lib/rancher/rke2/server/node-token')"
ansible-playbook playbooks/playbook-workers.yml
```

---

## 4. kubectl access

Copy kubeconfig from master1 (WireGuard VPN connected):

```bash
ssh ubuntu@<master_private_ip> \
  'sudo cat /etc/rancher/rke2/rke2.yaml' > kubeconfig.yaml
# Set server to https://api.<internal_domain>:6443 (see terraform output kubernetes_api_url)
# Use WireGuard so Route53 private names resolve inside the VPC
```

---

## 5. Traefik + AWS NLB

Terraform already created an **internal NLB** (ports 80/443) targeting worker NodePorts **30080/30443**. Install Traefik with NodePort, then use internal DNS:

```text
https://<app>.lla.internal  →  ingress NLB  →  Traefik  →  Service
```

---

## 6. Traefik Helm install

After workers are joined, install **Traefik** (not ingress-nginx):

```bash
# From repo root, with kubeconfig configured
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm install traefik traefik/traefik \
  --namespace traefik --create-namespace \
  -f kubernetes/traefik/helm-values.yaml
```

Full steps: **[docs/TRAEFIK.md](docs/TRAEFIK.md)** · NLB/Route53: **[docs/DNS-AND-LOAD-BALANCERS.md](docs/DNS-AND-LOAD-BALANCERS.md)**

---

## 7. Argo CD (GitOps)

After Traefik is running:

```bash
kubectl apply -k kubernetes/argocd
kubectl -n argocd get pods -w
```

UI (WireGuard + VPC DNS): **`http://argocd.lla.internal`**

```bash
# Admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

Full guide: **[docs/ARGOCD.md](docs/ARGOCD.md)**

---

## 8. Monitoring + AWS Secrets

1. Set secrets in AWS (see [docs/PRODUCTION.md](docs/PRODUCTION.md))
2. Install External Secrets + bootstrap credentials:

```bash
chmod +x scripts/bootstrap-eso-k8s-secret.sh
./scripts/bootstrap-eso-k8s-secret.sh
kubectl apply -f kubernetes/external-secrets/cluster-secret-store.yaml
```

3. Install Prometheus + Grafana: **[docs/MONITORING.md](docs/MONITORING.md)**

```bash
terraform output grafana_url
```

---

## Security notes

- Do not commit `terraform.tfvars`, `inventory.ini`, `group_vars/all.yml`, or `.pem` keys.
- Restrict `ssh_ingress_cidr` to your admin IP (/32). If you roam, `wireguard_ingress_cidr = 0.0.0.0/0` is acceptable (WireGuard key-based auth).
- WireGuard endpoint uses Elastic IP, so the server public IP stays stable across stop/start.
- NAT Gateway incurs ongoing AWS cost; destroy the stack when the lab is not needed.

---

## Destroy

```bash
cd terraform
terraform destroy
```
