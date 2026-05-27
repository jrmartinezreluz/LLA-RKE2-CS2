# Production posture (nonprod running as prod)

LLA-RKE2-CS2 is configured as a **production-style** single-AZ cluster. **Backups are not included** in this repo by client request.

---

## What Terraform enforces

| Control | Implementation |
|---------|----------------|
| Private control plane & workers | No public IPs on RKE2 nodes |
| Split security groups | `master-sg` vs `worker-sg` (API/join only on master; Traefik ports only on workers) |
| EBS encryption | All root volumes `encrypted = true` |
| IMDSv2 | `http_tokens = required` on all EC2 |
| Admin access | WireGuard only (no bastion) |
| IAM instance profile | Nodes read project secrets in Secrets Manager |
| Internal DNS + NLB | Private Route53 + internal NLBs |
| Secrets shells | AWS Secrets Manager secrets (placeholders — set real values) |

---

## What Ansible / RKE2 enforces

| Control | Implementation |
|---------|----------------|
| Secrets at rest (etcd) | `secrets-encryption: true` on server |
| Kernel hardening | `protect-kernel-defaults: true` |
| No bundled ingress | Traefik + Argo CD installed explicitly |
| Audit API | `audit-policy.yaml` on API server |

---

## AWS Secrets Manager

Terraform creates:

| Secret path | Purpose |
|-------------|---------|
| `lla-rke2-cs2/rke2/cluster-token` | Optional store for join token |
| `lla-rke2-cs2/monitoring/grafana-admin` | Grafana admin password |
| `lla-rke2-cs2/argocd/admin-password` | Argo CD admin (optional rotation) |
| `lla-rke2-cs2/bootstrap/eso-iam-credentials` | IAM user keys for External Secrets Operator |

**Set values** (replace `CHANGE_ME`):

```bash
aws secretsmanager put-secret-value \
  --secret-id lla-rke2-cs2/monitoring/grafana-admin \
  --secret-string "$(openssl rand -base64 24)"
```

Keep `ssh_ingress_cidr` restricted to `/32`. If operators move across networks, `wireguard_ingress_cidr = 0.0.0.0/0` is acceptable with strong WireGuard keys and peer rotation.

---

## Monitoring (Prometheus + Grafana)

See **[MONITORING.md](MONITORING.md)**.

- URL: `http://grafana.<internal_domain>` (default `http://grafana.lla.internal`)
- Metrics: Prometheus scrapes cluster + node exporters
- Grafana admin password: from Secrets Manager via External Secrets

---

## GitOps (Argo CD)

See **[ARGOCD.md](ARGOCD.md)**. Store repo credentials in Secrets Manager and sync with ExternalSecret.

---

## Not in scope (explicit)

- etcd / volume **backups**
- Multi-AZ control plane HA
- Public internet ingress

---

## Recommended next hardening

1. TLS on Traefik (`websecure`) + cert-manager  
2. Kubernetes **NetworkPolicies** (Calico)  
3. Pod Security **restricted** baseline  
4. Rotate External Secrets IAM keys periodically  
5. Remote Terraform **S3 backend** + state locking
