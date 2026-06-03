# ECR image pull on RKE2 nodes

IAM on the node role (`lla-rke2-cs2-ecr-pull`) allows `ecr:GetAuthorizationToken`, but **kubelet** must use the [ECR credential provider](https://docs.aws.amazon.com/AmazonECR/latest/userguide/k8s-ecr-auth.html) plugin.

RKE2 default paths (no extra `kubelet-arg` needed):

| Path | Purpose |
|------|---------|
| `/var/lib/rancher/credentialprovider/bin/ecr-credential-provider` | Plugin binary |
| `/var/lib/rancher/credentialprovider/config.yaml` | Provider config |

## Install on all nodes (SSH)

With Client VPN / WireGuard and SSH key:

```bash
chmod +x /ark/LLA-RKE2-CS2/scripts/run-ecr-credential-provider-on-nodes.sh
/ark/LLA-RKE2-CS2/scripts/run-ecr-credential-provider-on-nodes.sh
```

Single node:

```bash
ssh -i ~/.ssh/your-ec2-key-pair.pem ubuntu@<worker_private_ip> 'bash -s' \
  < /ark/LLA-RKE2-CS2/scripts/install-ecr-credential-provider.sh
```

## Install via Ansible

```bash
cd /ark/LLA-RKE2-CS2/ansible
ansible-playbook -i inventory.ini playbooks/playbook-ecr-credential-provider.yml
```

## After install

```bash
export KUBECONFIG=~/.kube/lla-rke2.yaml
kubectl -n erpnext-dev delete pod -l app.kubernetes.io/name=erpnext --field-selector=status.phase!=Running
kubectl -n argocd annotate application lla-cs2-erpnext-dev argocd.argoproj.io/refresh=hard --overwrite
kubectl -n erpnext-dev get pods
```

Pods should pull `<account-id>.dkr.ecr.<region>.amazonaws.com/lla-rke2-cs2/erpnext:sha-...` without `no basic auth credentials`.
