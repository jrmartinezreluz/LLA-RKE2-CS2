# GitHub App para Argo CD (recomendado)

Argo CD lee repos privados (`platform-gitops`, `app-charts`) usando una **GitHub App** — sin PAT personal en el cluster.

```text
GitHub App (read-only, repos seleccionados)
        │
        ▼
AWS Secrets Manager  lla-rke2-cs2/argocd/github-app
        │
        ▼
ExternalSecret → Secret repo-creds (namespace argocd)
        │
        ▼
ApplicationSet erpnext genera Applications dev/stg/prod
```

---

## Parte 1 — Crear la GitHub App (una vez)

1. Abre: https://github.com/settings/apps/new  
   (si usas org: `https://github.com/organizations/<org>/settings/apps/new`)

2. **GitHub App name:** `lla-rke2-argocd` (único en GitHub)

3. **Homepage URL:** `https://github.com/jrmartinezreluz` (cualquier URL válida)

4. **Webhook:** desactivado (uncheck *Active*)

5. **Repository permissions:**
   | Permiso | Acceso |
   |---------|--------|
   | Contents | **Read-only** |
   | Metadata | **Read-only** |

6. **Where can this app be installed?**  
   - Solo tu cuenta: *Only on this account*  
   - Org: *Any account* / *Only this organization* según corresponda

7. **Create GitHub App**

8. En la página de la app, anota:
   - **App ID** (número, ej. `123456`)

9. **Generate a private key** → descarga `*.pem` (guárdalo seguro, no en git)

10. **Install App** (menú izquierdo) → *Install* en tu cuenta/org  
    - Repositorios: **Only select** → marca:
      - `platform-gitops`
      - `app-charts`
      - (añade `erpnext-app` si el chart lo referencia)

11. Tras instalar, en la URL verás el **Installation ID**:  
    `https://github.com/settings/installations/<INSTALLATION_ID>`

---

## Parte 2 — Guardar credenciales en AWS

### Opción A — Script (recomendado)

```bash
cd /ark/LLA-RKE2-CS2

export GITHUB_APP_ID="123456"
export GITHUB_APP_INSTALLATION_ID="78901234"
export GITHUB_APP_PRIVATE_KEY_FILE="$HOME/Downloads/lla-rke2-argocd.*.pem"
export GITHUB_ORG_URL="https://github.com/jrmartinezreluz"

export AWS_PROFILE=lla
./scripts/setup-argocd-github-app-secret.sh
```

### Opción B — Consola AWS

Secrets Manager → `lla-rke2-cs2/argocd/github-app` → Edit secret value:

```json
{
  "url": "https://github.com/jrmartinezreluz",
  "githubAppID": "123456",
  "githubAppInstallationID": "78901234",
  "githubAppPrivateKey": "-----BEGIN RSA PRIVATE KEY-----\n...\n-----END RSA PRIVATE KEY-----\n"
}
```

Si el secret no existe aún:

```bash
cd /ark/LLA-RKE2-CS2/terraform
terraform apply   # crea el placeholder lla-rke2-cs2/argocd/github-app
```

---

## Parte 3 — Aplicar ExternalSecret en el cluster

Con VPN + kubectl:

```bash
kubectl apply -f /ark/LLA-RKE2-CS2/kubernetes/argocd/external-secret-github-app.yaml
```

O reaplica el kustomize de Argo CD:

```bash
kubectl apply --server-side --force-conflicts -k /ark/LLA-RKE2-CS2/kubernetes/argocd
```

Verificar:

```bash
kubectl -n argocd get externalsecret argocd-github-app-repos
kubectl -n argocd get secret github-app-repos -o yaml | grep secret-type
# debe mostrar: argocd.argoproj.io/secret-type: repo-creds
```

---

## Parte 4 — Comprobar Argo CD

```bash
# Forzar refresh del ApplicationSet
kubectl -n argocd annotate applicationset erpnext \
  argocd.argoproj.io/application-set-refresh=true --overwrite

kubectl -n argocd describe applicationset erpnext | tail -20
kubectl -n argocd get applications
```

Deberías ver algo como:

- `lla-cs2-erpnext-dev`
- `lla-cs2-erpnext-stg`
- `lla-cs2-erpnext-prod`

En la UI: http://argocd.lla.internal → **Settings → Repositories** — conexión OK vía credenciales de la app.

---

## Rotación de clave

1. GitHub App → *Generate a new private key*
2. `./scripts/setup-argocd-github-app-secret.sh` con el nuevo PEM
3. ESO refresca en ≤1h, o reinicia `argocd-repo-server`:

```bash
kubectl -n argocd rollout restart deployment argocd-repo-server
```

---

## Troubleshooting

| Síntoma | Acción |
|---------|--------|
| `Repository not found` | App instalada en los repos correctos; `url` en SM = `https://github.com/jrmartinezreluz` |
| ExternalSecret `SecretSyncedError` | Valor JSON válido en SM; ESO IAM puede leer el secret |
| ApplicationSet `Degraded` | `kubectl -n argocd logs deploy/argocd-applicationset-controller --tail=30` |
| PEM inválido | El JSON debe incluir saltos de línea reales en `githubAppPrivateKey` |

---

## Por qué GitHub App vs PAT

| | GitHub App | PAT personal |
|---|------------|----------------|
| Alcance | Solo repos elegidos | Todo `repo` |
| Token | Corto / rotación por app | Largo, ligado a tu usuario |
| Auditoría | Por instalación de app | Por usuario |
| Si sales de la empresa | Sigue funcionando | Se rompe |
