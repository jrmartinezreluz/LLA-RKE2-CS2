variable "project" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "private_subnet_id" {
  type = string
}

variable "client_cidr_block" {
  type        = string
  description = "CIDR assigned to VPN clients (must not overlap VPC or WireGuard CIDRs)"
  default     = "10.100.0.0/22"
}

variable "split_tunnel" {
  type        = bool
  description = "Only route VPC CIDR through VPN (recommended)"
  default     = true
}

variable "transport_protocol" {
  type        = string
  description = "udp or tcp"
  default     = "udp"
}

variable "vpn_port" {
  type    = number
  default = 443
}

variable "client_common_name" {
  type        = string
  description = "CN for the generated client certificate"
  default     = "operator-wsl"
}

variable "profile_output_path" {
  type        = string
  description = "Local path for generated .ovpn (gitignored)"
  default     = ""
}

variable "internal_domain" {
  type    = string
  default = "lla.internal"
}

variable "tags" {
  type    = map(string)
  default = {}
}
