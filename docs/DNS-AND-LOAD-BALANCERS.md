# Internal DNS (Route53) and AWS Load Balancers

LLA-RKE2-CS2 does **not** use an external NGINX EC2 load balancer (CS1 pattern). Traffic enters the VPC through **internal Network Load Balancers** and **Route53 private DNS**.

---

## Why NLB instead of ALB?

Application Load Balancers require subnets in **at least two Availability Zones**. This project is **single-AZ** by design. **Internal NLBs** forward TCP to RKE2 and Traefik NodePorts in one AZ.

| Service | AWS LB | Listener | Target |
|---------|--------|----------|--------|
| Kubernetes API | Internal NLB | TCP 6443 | master1:6443 |
| RKE2 join | Same NLB | TCP 9345 | master1:9345 |
| HTTP ingress | Internal NLB | TCP 80 | workers:30080 |
| HTTPS ingress | Same NLB | TCP 443 | workers:30443 |

Traefik remains **NodePort** behind the ingress NLB (see [TRAEFIK.md](TRAEFIK.md)).

---

## Route53 private hosted zone

Terraform creates a **private** hosted zone (default `lla.internal`) associated with the VPC.

| Record | Points to | Use |
|--------|-----------|-----|
| `api.<domain>` | K8s NLB | `kubectl`, API TLS SAN |
| `join.<domain>` | K8s NLB | RKE2 agent join (`:9345`) |
| `ingress.<domain>` | Ingress NLB | Traefik HTTP/HTTPS entry |
| `argocd.<domain>` | Ingress NLB | Argo CD UI (GitOps) |
| `*.<domain>` (optional) | Ingress NLB | Per-app Ingress hostnames |

Resolve names only from **inside the VPC** (WireGuard client with `AllowedIPs` including VPC CIDR, or another host in the VPC).

For WireGuard clients, set **DNS to the VPC resolver** (e.g. `10.0.0.2` for a `10.0.0.0/16` VPC) in `wg0.conf` so `api.lla.internal` resolves:

```ini
[Interface]
DNS = 10.0.0.2
```

### WSL2 (`curl` / browser still “Could not resolve host”)

WSL often sets `/etc/resolv.conf` to `nameserver 10.255.255.254`, which does **not** know `*.lla.internal`. `resolvectl query argocd.lla.internal` may work while `curl` fails.

Use the project script (sets `resolvectl domain` + `nameserver 127.0.0.53`):

```bash
sudo /ark/LLA-RKE2-CS2/scripts/wg-down-wsl.sh
sudo /ark/LLA-RKE2-CS2/scripts/wg-up-wsl.sh
curl -sS -o /dev/null -w '%{http_code}\n' http://argocd.lla.internal/
```

One-off fix without re-running the script:

```bash
sudo resolvectl domain lla-wg lla.internal
sudo rm -f /etc/resolv.conf
printf 'nameserver 127.0.0.53\nsearch lla.internal\n' | sudo tee /etc/resolv.conf
```

---

## Terraform variables

```hcl
internal_domain     = "lla.internal"
api_record_name     = "api"
join_record_name    = "join"
ingress_record_name = "ingress"
wildcard_ingress    = true
```

Outputs after `terraform apply`:

```bash
terraform output kubernetes_api_url
terraform output api_fqdn
terraform output ingress_fqdn
terraform output route53_zone_id
```

---

## kubectl via internal DNS

With WireGuard connected (VPC DNS `10.0.0.2`):

```bash
# kubeconfig server URL — use api FQDN
export KUBECONFIG=./kubeconfig.yaml
# Set clusters[].cluster.server to https://api.lla.internal:6443
kubectl get nodes
```

Ansible `rke2_server` adds `api_fqdn` and `join_fqdn` to `tls-san`. Workers join `https://join.<domain>:9345`.

---

## Application URLs

Create Traefik `Ingress` resources with `host: myapp.lla.internal`. With `wildcard_ingress = true`, `*.lla.internal` resolves to the ingress NLB; Traefik routes by `Host` header.

Example:

```text
https://myapp.lla.internal/   → ingress NLB :443 → worker NodePort 30443 → Traefik → Service
```

---

## Health checks

Ingress NLB target groups health-check TCP **30080** / **30443**. Targets stay **unhealthy** until Traefik Helm is installed. That is expected between Ansible and Helm steps.

---

## Not in scope

- Public internet-facing ALB/NLB (internal only)
- External NGINX EC2
- Route53 public hosted zone (add separately if needed)
