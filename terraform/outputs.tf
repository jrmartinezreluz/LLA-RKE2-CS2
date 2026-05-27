output "aws_region" {
  value = var.aws_region
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "vpc_cidr" {
  value = module.vpc.vpc_cidr
}

output "availability_zone" {
  value = var.availability_zone
}

output "wireguard_public_ip" {
  value = module.compute.wireguard_public_ip
}

output "master_private_ip" {
  value = module.compute.master_private_ip
}

output "worker_private_ips" {
  value = module.compute.worker_private_ips
}

output "internal_domain" {
  value = module.loadbalancing.internal_domain
}

output "api_fqdn" {
  value = module.loadbalancing.api_fqdn
}

output "join_fqdn" {
  value = module.loadbalancing.join_fqdn
}

output "ingress_fqdn" {
  value = module.loadbalancing.ingress_fqdn
}

output "kubernetes_api_url" {
  value = module.loadbalancing.kubernetes_api_url
}

output "k8s_nlb_dns_name" {
  value = module.loadbalancing.k8s_nlb_dns_name
}

output "ingress_nlb_dns_name" {
  value = module.loadbalancing.ingress_nlb_dns_name
}

output "route53_zone_id" {
  value = module.loadbalancing.route53_zone_id
}

output "argocd_fqdn" {
  value = module.loadbalancing.argocd_fqdn
}

output "argocd_url" {
  value = module.loadbalancing.argocd_url
}

output "grafana_fqdn" {
  value = module.loadbalancing.grafana_fqdn
}

output "grafana_url" {
  value = module.loadbalancing.grafana_url
}

output "secrets_manager_secret_names" {
  value = module.secrets.secret_names
}

output "eso_credentials_secret_name" {
  value = module.secrets.eso_credentials_secret_name
}

output "ansible_vars" {
  description = "Values for ansible/group_vars/all.yml (also used by sync-ansible-vars.sh)"
  value       = merge(module.compute.ansible_vars, module.loadbalancing.ansible_vars)
}
