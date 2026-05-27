# Public reference repository — what must stay local

This repo is safe to publish as a **pattern reference** when these files are **never committed**:

| File / pattern | Contains |
|----------------|----------|
| `ansible/group_vars/all.yml` | Real IPs, WireGuard peer keys, SSH key paths |
| `ansible/inventory.ini` | Host IPs |
| `ansible/wg-client.conf`, `*-wg.conf`, `lla-windows-*.conf` | VPN private keys |
| `ansible/*.key`, `*.pem` | SSH / WireGuard keys |
| `terraform/terraform.tfvars` | Account-specific settings |
| `terraform/terraform.tfstate*` | AWS account ID, ARNs, instance IDs, **IAM access keys** |
| `*.crt` (exported CA) | Internal CA (optional to share; not a private key) |

## Verified not in git history

- WireGuard private keys
- AWS access keys / secret keys
- Real passwords (only `CHANGE_ME` placeholders in Terraform)
- `terraform.tfstate`

## Before each push

```bash
git status
git diff --cached
git grep -E 'PrivateKey =|AKIA|876908012182|BEGIN (RSA|OPENSSH|EC )' HEAD || echo OK
```

## Private backup repository

For real `all.yml`, inventory, `terraform.tfvars`, and WireGuard configs, use a **separate private repo**. See **[PRIVATE-REPO.md](PRIVATE-REPO.md)** and `scripts/init-private-repo.sh`.

## If secrets were committed by mistake

1. Rotate all exposed credentials (WireGuard peers, AWS IAM keys, Argo/Grafana passwords).
2. Remove from history (`git filter-repo` or BFG) — deleting a file in a new commit is **not** enough for public repos.
