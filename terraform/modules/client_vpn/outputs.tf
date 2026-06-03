output "endpoint_id" {
  value = aws_ec2_client_vpn_endpoint.main.id
}

output "endpoint_dns_name" {
  value = aws_ec2_client_vpn_endpoint.main.dns_name
}

output "client_cidr_block" {
  value = var.client_cidr_block
}

output "security_group_id" {
  value = aws_security_group.endpoint.id
}

output "profile_output_path" {
  value = var.profile_output_path != "" ? local_file.client_profile[0].filename : null
}

output "ovpn_profile" {
  value     = local.ovpn_profile
  sensitive = true
}
