# AWS Client VPN (OpenVPN) — LLA-RKE2-CS2

Acceso admin a la VPC desde **WSL** usando **AWS Client VPN** (OpenVPN managed). Alternativa más estable que WireGuard + `wireguard-go` en WSL.

---

## Arquitectura

```text
WSL (openvpn)
     │ UDP 443
     ▼
AWS Client VPN Endpoint  (10.100.0.0/22 client CIDR)
     │
     ▼
VPC 10.0.0.0/16  →  RKE2, RDS, Argo CD, Route53 private (lla.internal)
```

- **Split tunnel:** solo tráfico a `10.0.0.0/16` va por la VPN.
- **DNS:** resolver VPC `10.0.0.2` para `*.lla.internal`.
- **Auth:** certificados TLS (mutual); perfil generado por Terraform.

WireGuard sigue disponible durante la migración; **no uses ambos a la vez** (el script `client-vpn-up-wsl.sh` baja WireGuard automáticamente).

---

## 1. Provisionar (Terraform)

En `terraform/terraform.tfvars`:

```hcl
enable_client_vpn       = true
client_vpn_cidr         = "10.100.0.0/22"
client_vpn_split_tunnel = true
client_vpn_client_name  = "operator-wsl"
```

Aplicar **solo desde** `LLA-RKE2-CS2/terraform/`:

```bash
cd /ark/LLA-RKE2-CS2/terraform
export AWS_PROFILE=lla
aws sso login --profile lla
terraform init -upgrade   # tls + local providers
terraform plan
terraform apply
```

Genera:

| Output / archivo | Descripción |
|------------------|-------------|
| `ansible/client-vpn.ovpn` | Perfil OpenVPN (gitignored, permisos 600) |
| `client_vpn_endpoint_dns` | DNS del endpoint |
| SG master/worker | Reglas SSH/API para `10.100.0.0/22` |

**Coste aproximado:** ~USD 0.10/h endpoint + ~USD 0.05/h por conexión.

---

## 2. Cliente WSL

```bash
sudo apt update && sudo apt install -y openvpn

# Subir VPN
sudo /ark/LLA-RKE2-CS2/scripts/client-vpn-up-wsl.sh

# Probar
resolvectl query api.lla.internal
ssh ubuntu@<master_private_ip> 'echo ok'
export KUBECONFIG=~/.kube/lla-rke2.yaml
kubectl cluster-info    # OpenVPN suele funcionar mejor que WireGuard

# Bajar VPN
sudo /ark/LLA-RKE2-CS2/scripts/client-vpn-down-wsl.sh
```

Si `kubectl` local sigue fallando, usar `scripts/kubectl-lla.sh` (kubectl en el master vía SSH).

---

## 3. Setup completo (una vez)

```bash
/ark/LLA-RKE2-CS2/scripts/setup-lla-client.sh   # SSH config + kubeconfig URL
```

---

## 4. Migración WireGuard → Client VPN

1. `terraform apply` con `enable_client_vpn = true`
2. Probar Client VPN desde WSL durante unos días
3. Opcional: apagar EC2 WireGuard o restringir `wireguard_ingress_cidr`
4. Eliminar `wg-up-wsl.sh` del flujo diario

---

## 5. Renovar certificado cliente

El certificado cliente dura ~1 año. Para rotar:

```bash
cd terraform
terraform taint 'module.client_vpn[0].tls_locally_signed_cert.client'
terraform apply
# Nuevo ansible/client-vpn.ovpn
```

---

## Troubleshooting

| Síntoma | Acción |
|---------|--------|
| `Missing profile` | `terraform apply` con `enable_client_vpn = true` |
| DNS no resuelve | VPN arriba; `resolvectl query api.lla.internal` |
| SSH timeout | `client-vpn-down` + `client-vpn-up`; revisar SG |
| Conflicto rutas | No correr WireGuard y Client VPN a la vez |

Logs OpenVPN: `/run/client-vpn/openvpn.log`

CloudWatch: `/aws/client-vpn/lla-rke2-cs2`
