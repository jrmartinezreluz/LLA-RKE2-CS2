variable "project" {
  type        = string
  description = "Resource name prefix"
  default     = "lla-rke2-cs2"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "availability_zone" {
  type    = string
  default = "us-east-1a"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  type    = string
  default = "10.0.11.0/24"
}

variable "key_name" {
  type        = string
  description = "EC2 key pair name in the target region"
}

variable "ami_id" {
  description = "Ubuntu 24.04 LTS AMI for the chosen region"
  type        = string
  default     = "ami-0731becbf832f281e"
}

variable "instance_wireguard" {
  type    = string
  default = "t3.small"
}

variable "instance_master" {
  type    = string
  default = "t3.large"
}

variable "instance_workers" {
  type    = string
  default = "t3.medium"
}

variable "ssh_ingress_cidr" {
  description = "CIDR allowed for SSH to WireGuard instance"
  type        = string
  default     = "0.0.0.0/0"
}

variable "wireguard_vpn_cidr" {
  description = "WireGuard client tunnel CIDR (SSH/API to private nodes from VPN)"
  type        = string
  default     = "10.8.0.0/24"
}

variable "wireguard_ingress_cidr" {
  description = "CIDR allowed for WireGuard UDP 51820"
  type        = string
  default     = "0.0.0.0/0"
}

variable "root_volume_size_gb" {
  type    = number
  default = 80
}

variable "internal_domain" {
  description = "Route53 private hosted zone for internal DNS (associated with VPC)"
  type        = string
  default     = "lla.internal"
}

variable "api_record_name" {
  type    = string
  default = "api"
}

variable "join_record_name" {
  type    = string
  default = "join"
}

variable "ingress_record_name" {
  type    = string
  default = "ingress"
}

variable "wildcard_ingress" {
  description = "Create *.internal_domain Route53 alias to ingress NLB"
  type        = bool
  default     = true
}

variable "argocd_record_name" {
  description = "Route53 record name for Argo CD UI (argocd.<internal_domain>)"
  type        = string
  default     = "argocd"
}

variable "grafana_record_name" {
  description = "Route53 record name for Grafana (grafana.<internal_domain>)"
  type        = string
  default     = "grafana"
}

variable "secrets_recovery_window_days" {
  description = "Secrets Manager recovery window when deleting secrets"
  type        = number
  default     = 7
}
