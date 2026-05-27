# Traefik Ingress Controller on LLA-RKE2-CS2

This cluster uses **Traefik** as the Kubernetes ingress controller. It does **not** use NGINX Ingress Controller.

RKE2 Ansible roles already disable the bundled charts:

- `rke2-ingress` (default Traefik packaged with RKE2)
- `rke2-ingress-nginx`

Traefik is installed separately via Helm after the cluster is up.

North-south traffic uses an **AWS internal NLB** and **Route53 private DNS** (not an NGINX EC2 LB). See **[DNS-AND-LOAD-BALANCERS.md](DNS-AND-LOAD-BALANCERS.md)**.

---

## Prerequisites

- Cluster bootstrapped (master + workers)
- `kubectl` and `helm` on your workstation
- Kubeconfig pointing at the cluster (WireGuard VPN required)
- Helm 3

Install CLI tools on master1 (optional, SSH over VPN):

```bash
# kubectl — RKE2 places it on nodes
export PATH="$PATH:/var/lib/rancher/rke2/bin"
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml

# helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

---

## 1. Label worker nodes

```bash
kubectl get nodes
kubectl label node <worker1-name> node-role.kubernetes.io/worker=worker --overwrite
kubectl label node <worker2-name> node-role.kubernetes.io/worker=worker --overwrite
kubectl label node <worker3-name> node-role.kubernetes.io/worker=worker --overwrite
```

---

## 2. Install Traefik via Helm

Add the Traefik Helm repository:

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update
```

Install with **NodePort** on workers. Terraform’s **ingress NLB** forwards TCP 80→30080 and 443→30443 to all workers:

```bash
helm install traefik traefik/traefik \
  --namespace traefik --create-namespace \
  --values kubernetes/traefik/helm-values.yaml
```

Or inline equivalent:

```bash
helm install traefik traefik/traefik \
  --namespace traefik --create-namespace \
  --set ingressClass.enabled=true \
  --set ingressClass.isDefaultClass=true \
  --set ingressClass.name=traefik \
  --set service.type=NodePort \
  --set ports.web.nodePort=30080 \
  --set ports.websecure.nodePort=30443 \
  --set nodeSelector."node-role\.kubernetes\.io/worker"=worker
```

Verify:

```bash
kubectl get pods -n traefik
kubectl get svc -n traefik
kubectl get ingressclass
```

Expected default IngressClass: **traefik**.

---

## 3. Sample Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: demo
  namespace: default
spec:
  ingressClassName: traefik
  rules:
    - host: demo.lla.internal
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: demo
                port:
                  number: 80
```

Reach the app via internal DNS (WireGuard + VPC):

```text
http://demo.lla.internal      → ingress NLB :80  → NodePort 30080
https://demo.lla.internal     → ingress NLB :443 → NodePort 30443
```

Wildcard `*.lla.internal` is created when `wildcard_ingress = true` in Terraform.

**Argo CD** uses host `argocd.lla.internal` — install after Traefik: [ARGOCD.md](ARGOCD.md).

---

## 4. TLS (optional)

For production, configure Traefik certificates via:

- `cert-manager` + Let's Encrypt, or
- TLS store / default certificate in Traefik Helm values

See [Traefik Helm chart documentation](https://github.com/traefik/traefik-helm-chart) for `tlsStore` and `additionalArguments`.

---

## Comparison with CS1 lab

| CS1 (AWSK8S-RKE2-CS1) | LLA-RKE2-CS2 |
|------------------------|--------------|
| Ingress NGINX (Helm) | **Traefik** (Helm) |
| External NGINX EC2 LB | **Internal AWS NLB** + Route53 private zone |
| Public/direct API | `api.lla.internal` via internal NLB |
