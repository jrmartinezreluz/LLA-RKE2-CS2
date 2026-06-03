# WSL + WireGuard + RKE2 — por qué falla y cómo dejarlo estable

Sí: **casi todos los problemas vienen de la VPN en WSL**, pero no es un solo bug. Son **cuatro capas** distintas que se superponen.

---

## Las 4 capas del problema

| Capa | Síntoma | Causa | Fix |
|------|---------|-------|-----|
| **1. MTU** | SSH/scp se cuelgan, archivos vacíos | Paquetes TCP demasiado grandes para el túnel (WSL → WG → internet → AWS) | `MTU = 1280` + MSS clamp |
| **2. IP QoS / DSCP** | SSH KEX colgado, `kubectl` TLS timeout | OpenSSH y Go marcan paquetes con prioridad; el túnel los pierde | `IPQoS none` (SSH) + `iptables DSCP --set-dscp 0` (wg-up) |
| **3. wireguard-go** | Más frágil que el módulo kernel | Userspace TUN en WSL añade overhead | Preferir **kernel WireGuard** si WSL lo soporta |
| **4. WSL + stdin** | `scp`, `cat > remoto`, pipes largos fallan | Bug/limitación de WSL con redirección stdin sobre SSH | `kubectl-lla.sh` (kubectl en el master), base64 para YAML |

El cluster RKE2 **está bien**. Desde dentro del VPC (`curl`, `kubectl` en el master) todo responde. Lo que falla es **el camino WSL → VPN → VPC** con ciertos clientes.

---

## Configuración recomendada (cliente WSL)

Archivo `ansible/wg-client.conf` (copiar desde `wg-client.conf.example`; no commitear claves):

```ini
[Interface]
Address = 10.8.0.2/24
DNS = 10.0.0.2
MTU = 1280          # crítico

[Peer]
Endpoint = <ip-publica>:51820
AllowedIPs = 10.0.0.0/16,10.8.0.0/24   # solo VPC + VPN (split tunnel)
PersistentKeepalive = 25                # mantiene NAT/firewall abiertos
```

Levantar VPN (aplica MTU + iptables MSS + DSCP):

```bash
sudo /ark/LLA-RKE2-CS2/scripts/wg-up-wsl.sh
```

Una sola vez (SSH/git):

```bash
/ark/LLA-RKE2-CS2/scripts/setup-lla-client.sh
```

---

## Configuración recomendada (servidor WireGuard en AWS)

En el repo, el role `wireguard` ahora incluye en `wg0.conf`:

- `MTU = 1280`
- **MSS clamp** en `FORWARD` (PostUp/PostDown)

Para aplicarlo en el servidor:

```bash
cd /ark/LLA-RKE2-CS2/ansible
ansible-playbook -i inventory.ini playbooks/playbook-wireguard.yml
```

(Solo cuando tengas acceso SSH al host `[wireguard]`; no requiere VPN.)

---

## Qué usar para cada herramienta

| Herramienta | Desde WSL | Notas |
|-------------|-----------|-------|
| **SSH / scp** | ✅ Directo | Con `~/.ssh/ssh-lla.conf` instalado |
| **curl / browser** | ✅ Directo | API, Argo CD UI |
| **git push** | ✅ Directo | `IPQoS none` en github hosts |
| **kubectl local** | ⚠️ A menudo falla | Cliente Go + VPN; usar `kubectl-lla.sh` |
| **kubectl apply -f** | ⚠️ Usar wrapper | `kubectl-lla.sh apply -f ...` (base64, sin scp) |

```bash
# kubectl fiable desde WSL
/ark/LLA-RKE2-CS2/scripts/kubectl-lla.sh get nodes
/ark/LLA-RKE2-CS2/scripts/kubectl-lla.sh apply -f platform-gitops/argocd/applicationsets/erpnext.yaml
```

---

## Comprobar que la VPN está sana

```bash
ip link show lla-wg | grep mtu          # 1280
ssh ubuntu@<master_private_ip> 'echo ok'        # ok en ~2s
curl -sk -o /dev/null -w '%{http_code}\n' https://api.lla.internal:6443/version   # 401
resolvectl query api.lla.internal       # 10.0.x.x
```

Si SSH empieza a hacer timeout: **bajar y subir la VPN** (estado stale del túnel):

```bash
sudo /ark/LLA-RKE2-CS2/scripts/wg-down-wsl.sh
sudo /ark/LLA-RKE2-CS2/scripts/wg-up-wsl.sh
```

---

## ¿Se puede evitar el 100% de problemas solo con WireGuard?

**Casi.** Con MTU + MSS (cliente y servidor) + SSH config + split tunnel, **SSH, DNS, curl y git** quedan estables.

**`kubectl` local desde WSL** puede seguir fallando por el cliente Go aunque la API responda bien a curl. Eso no es un fallo del cluster: es la combinación **Go + WSL + túnel**. La solución práctica es `kubectl-lla.sh` (ejecuta kubectl en el master por SSH).

Si en el futuro WSL usa **WireGuard kernel** de forma estable (tu kernel ya lo anuncia), prueba de nuevo `kubectl cluster-info` directo tras `wg-up-wsl.sh` — a veces elimina la capa 3 por completo.
