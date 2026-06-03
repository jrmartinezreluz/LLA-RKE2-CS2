terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    tls = {
      source = "hashicorp/tls"
    }
    local = {
      source = "hashicorp/local"
    }
  }
}

# --- PKI for mutual TLS (server + client certs) ---

resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem = tls_private_key.ca.private_key_pem

  subject {
    common_name = "${var.project} Client VPN CA"
  }

  is_ca_certificate     = true
  validity_period_hours = 87600

  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]
}

resource "tls_private_key" "server" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "server" {
  private_key_pem = tls_private_key.server.private_key_pem

  subject {
    common_name = "server.${var.project}.clientvpn"
  }
}

resource "tls_locally_signed_cert" "server" {
  cert_request_pem   = tls_cert_request.server.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = 8760

  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "server" {
  private_key       = tls_private_key.server.private_key_pem
  certificate_body  = tls_locally_signed_cert.server.cert_pem
  certificate_chain = tls_self_signed_cert.ca.cert_pem

  tags = merge(var.tags, {
    Name = "${var.project}-client-vpn-server"
  })
}

resource "aws_acm_certificate" "client_root" {
  private_key      = tls_private_key.ca.private_key_pem
  certificate_body = tls_self_signed_cert.ca.cert_pem

  tags = merge(var.tags, {
    Name = "${var.project}-client-vpn-ca"
  })
}

resource "tls_private_key" "client" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "client" {
  private_key_pem = tls_private_key.client.private_key_pem

  subject {
    common_name = var.client_common_name
  }
}

resource "tls_locally_signed_cert" "client" {
  cert_request_pem   = tls_cert_request.client.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = 8760

  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "client_auth",
  ]
}

# --- Client VPN endpoint ---

resource "aws_cloudwatch_log_group" "client_vpn" {
  name              = "/aws/client-vpn/${var.project}"
  retention_in_days = 14

  tags = var.tags
}

resource "aws_cloudwatch_log_stream" "client_vpn" {
  name           = "connections"
  log_group_name = aws_cloudwatch_log_group.client_vpn.name
}

resource "aws_security_group" "endpoint" {
  name_prefix = "${var.project}-client-vpn-"
  description = "AWS Client VPN endpoint"
  vpc_id      = var.vpc_id

  ingress {
    description = "Client VPN"
    from_port   = var.vpn_port
    to_port     = var.vpn_port
    protocol    = var.transport_protocol
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project}-client-vpn-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_ec2_client_vpn_endpoint" "main" {
  description            = "${var.project} Client VPN (WSL / admin)"
  server_certificate_arn = aws_acm_certificate.server.arn
  client_cidr_block      = var.client_cidr_block
  split_tunnel           = var.split_tunnel
  transport_protocol     = var.transport_protocol
  vpn_port               = var.vpn_port
  vpc_id                 = var.vpc_id
  security_group_ids     = [aws_security_group.endpoint.id]

  # VPC resolver — required for Route53 private zone (lla.internal)
  dns_servers = [cidrhost(var.vpc_cidr, 2)]

  authentication_options {
    type                       = "certificate-authentication"
    root_certificate_chain_arn = aws_acm_certificate.client_root.arn
  }

  connection_log_options {
    enabled               = true
    cloudwatch_log_group  = aws_cloudwatch_log_group.client_vpn.name
    cloudwatch_log_stream = aws_cloudwatch_log_stream.client_vpn.name
  }

  tags = merge(var.tags, {
    Name = "${var.project}-client-vpn"
  })
}

resource "aws_ec2_client_vpn_network_association" "private" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.main.id
  subnet_id              = var.private_subnet_id
}

resource "aws_ec2_client_vpn_authorization_rule" "vpc" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.main.id
  target_network_cidr    = var.vpc_cidr
  authorize_all_groups   = true
  description            = "Allow authenticated clients into VPC"

  timeouts {
    create = "20m"
  }
}

# Route to VPC CIDR is created automatically when the subnet is associated.
# Do not add aws_ec2_client_vpn_route here — AWS returns InvalidClientVpnDuplicateRoute.

locals {
  # Wildcard DNS: only *.cvpn-endpoint-... resolves (not bare cvpn-endpoint-...).
  # remote-random-hostname prepends random hex → abc123.cvpn-endpoint-...
  endpoint_fqdn = replace(aws_ec2_client_vpn_endpoint.main.dns_name, "*.", "")

  ovpn_profile = <<-EOT
client
dev tun
proto ${var.transport_protocol}
remote ${local.endpoint_fqdn} ${var.vpn_port}
remote-random-hostname
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
verb 3
reneg-sec 0

# Route53 private DNS (VPC resolver)
dhcp-option DNS ${cidrhost(var.vpc_cidr, 2)}
dhcp-option DOMAIN ${var.internal_domain}

<ca>
${tls_self_signed_cert.ca.cert_pem}
</ca>

<cert>
${tls_locally_signed_cert.client.cert_pem}
</cert>

<key>
${tls_private_key.client.private_key_pem}
</key>
EOT
}

resource "local_file" "client_profile" {
  count = var.profile_output_path != "" ? 1 : 0

  filename             = var.profile_output_path
  directory_permission = "0755"
  file_permission      = "0600"
  content              = local.ovpn_profile
}
