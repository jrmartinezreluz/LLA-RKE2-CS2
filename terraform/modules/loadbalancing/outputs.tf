output "route53_zone_id" {
  value = aws_route53_zone.private.zone_id
}

output "internal_domain" {
  value = var.internal_domain
}

output "api_fqdn" {
  value = aws_route53_record.api.fqdn
}

output "join_fqdn" {
  value = aws_route53_record.join.fqdn
}

output "ingress_fqdn" {
  value = aws_route53_record.ingress.fqdn
}

output "argocd_fqdn" {
  value = aws_route53_record.argocd.fqdn
}

output "argocd_url" {
  value = "http://${aws_route53_record.argocd.fqdn}"
}

output "grafana_fqdn" {
  value = aws_route53_record.grafana.fqdn
}

output "grafana_url" {
  value = "http://${aws_route53_record.grafana.fqdn}"
}

output "wildcard_fqdn" {
  value = var.wildcard_ingress ? aws_route53_record.ingress_wildcard[0].fqdn : null
}

output "k8s_nlb_dns_name" {
  value = aws_lb.k8s.dns_name
}

output "ingress_nlb_dns_name" {
  value = aws_lb.ingress.dns_name
}

output "kubernetes_api_url" {
  value = "https://${aws_route53_record.api.fqdn}:6443"
}

output "ansible_vars" {
  value = {
    internal_domain   = var.internal_domain
    api_fqdn          = aws_route53_record.api.fqdn
    join_fqdn         = aws_route53_record.join.fqdn
    ingress_fqdn      = aws_route53_record.ingress.fqdn
    kubernetes_api_url = "https://${aws_route53_record.api.fqdn}:6443"
    k8s_nlb_dns_name  = aws_lb.k8s.dns_name
    ingress_nlb_dns_name = aws_lb.ingress.dns_name
    argocd_fqdn          = aws_route53_record.argocd.fqdn
    argocd_url           = "http://${aws_route53_record.argocd.fqdn}"
    grafana_fqdn         = aws_route53_record.grafana.fqdn
    grafana_url          = "http://${aws_route53_record.grafana.fqdn}"
  }
}
