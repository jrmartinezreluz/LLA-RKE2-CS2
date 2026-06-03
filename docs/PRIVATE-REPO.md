# Private operations repository

Use a **second GitHub repository (private)** for real deployment values. Keep the public [LLA-RKE2-CS2](https://github.com/jrmartinezreluz/LLA-RKE2-CS2) repo as a sanitized reference.

| Repository | Visibility | Contents |
|------------|------------|----------|
| `LLA-RKE2-CS2` | Public | Templates, docs, Kubernetes, Terraform modules |
| `LLA-RKE2-CS2-private` | **Private** | `all.yml`, `inventory.ini`, `terraform.tfvars`, WireGuard `*.conf` |

## What the private repo should include

| File | Why |
|------|-----|
| `ansible/group_vars/all.yml` | IPs, WireGuard peers, SSH key path |
| `ansible/inventory.ini` | Ansible hosts |
| `ansible/wg-client.conf`, `*-wg.conf` | VPN client configs |
| `terraform/terraform.tfvars` | Environment sizing, CIDRs, domain |

## What NOT to commit (even in private)

| File | Why |
|------|-----|
| `terraform/terraform.tfstate*` | AWS account ID, ARNs, **IAM access keys** |
| `*.pem` | EC2 SSH private keys — use `~/.ssh/` only |
| `.terraform/` | Provider cache (large, reproducible) |

---

## One-command bootstrap (from WSL)

```bash
/ark/LLA-RKE2-CS2/scripts/init-private-repo.sh
```

Defaults:

- Destination: `/ark/LLA-RKE2-CS2-private`
- GitHub remote: `git@github-arkhadia:jrmartinezreluz/LLA-RKE2-CS2-private.git`

Override:

```bash
GITHUB_USER=your-org REPO_NAME=my-lla-ops DEST=/path/to/ops \
  /ark/LLA-RKE2-CS2/scripts/init-private-repo.sh
```

Then on GitHub: **New repository** → name `LLA-RKE2-CS2-private` → **Private** → empty (no README).

```bash
cd /ark/LLA-RKE2-CS2-private
git push -u origin main
```

---

## Manual setup

```bash
cp -a /ark/LLA-RKE2-CS2 /ark/LLA-RKE2-CS2-private
rm -rf /ark/LLA-RKE2-CS2-private/.git
cp /ark/LLA-RKE2-CS2-private/.gitignore.private.example \
   /ark/LLA-RKE2-CS2-private/.gitignore
cd /ark/LLA-RKE2-CS2-private
git init
git add -A
git status   # confirm all.yml / inventory / tfvars are listed
git commit -m "Private LLA RKE2 ops configuration"
git remote add origin git@github-arkhadia:jrmartinezreluz/LLA-RKE2-CS2-private.git
git push -u origin main
```

---

## Sync public → private (after cluster work)

When `LLA-RKE2-CS2` gains new docs, Terraform modules, Kubernetes manifests, or scripts:

```bash
/ark/LLA-RKE2-CS2/scripts/sync-private-repo.sh
cd /ark/LLA-RKE2-CS2-private
git status
git add -A
git commit -m "Sync from public LLA-RKE2-CS2: <short summary>"
git push origin main
```

The script **rsyncs** the public tree into the private clone and **restores** ops files (`all.yml`, `inventory.ini`, `terraform.tfvars`, WireGuard `*.conf`, keys). It does not copy `.git`, `.terraform`, or `terraform.tfstate*`.

---

## Day-to-day workflow

1. **Public repo** — patterns, docs, Helm/K8s manifest changes → PR for reference.
2. **Private repo** — IP changes, new WireGuard peer, `tfvars` tweaks; run `sync-private-repo.sh` to pull the rest.
3. Clone both on a new machine:

```bash
git clone git@github-arkhadia:jrmartinezreluz/LLA-RKE2-CS2.git
git clone git@github-arkhadia:jrmartinezreluz/LLA-RKE2-CS2-private.git
# Work in private copy; symlink or copy ops files into public tree if you keep one workspace
```

---

## Access control

- Limit GitHub collaborators on the private repo.
- Enable branch protection on `main` if more than one operator.
- Rotate WireGuard peers and AWS keys if a laptop or token is lost.

See also [SECURITY-PUBLIC-REPO.md](SECURITY-PUBLIC-REPO.md).
