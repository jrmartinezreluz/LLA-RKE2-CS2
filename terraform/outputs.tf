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

output "erpnext_ecr_repository_urls" {
  value = var.enable_erpnext_ecr ? module.ecr[0].repository_urls : {}
}

output "erpnext_github_actions_role_arn" {
  value       = var.enable_erpnext_ecr ? module.github_oidc[0].role_arn : null
  description = "AWS_ROLE_ARN for erpnext-app GitHub Actions"
}

output "erpnext_rds_endpoint" {
  value = var.enable_erpnext_rds ? module.rds[0].endpoint : null
}

output "erpnext_db_secret_names" {
  value = var.enable_erpnext_rds ? module.rds[0].env_db_secret_names : {}
}

output "client_vpn_endpoint_id" {
  value = var.enable_client_vpn ? module.client_vpn[0].endpoint_id : null
}

output "client_vpn_endpoint_dns" {
  value = var.enable_client_vpn ? module.client_vpn[0].endpoint_dns_name : null
}

output "client_vpn_cidr" {
  value = var.enable_client_vpn ? module.client_vpn[0].client_cidr_block : null
}

output "client_vpn_profile_path" {
  description = "Generated OpenVPN profile (gitignored); run scripts/client-vpn-up-wsl.sh"
  value       = var.enable_client_vpn ? module.client_vpn[0].profile_output_path : null
}

output "ansible_vars" {
  description = "Values for ansible/group_vars/all.yml (also used by sync-ansible-vars.sh)"
  value       = merge(module.compute.ansible_vars, module.loadbalancing.ansible_vars)
}
