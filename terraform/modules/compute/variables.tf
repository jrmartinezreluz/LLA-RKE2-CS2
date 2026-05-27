variable "project" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "key_name" {
  type = string
}

variable "ami_id" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "public_subnet_id" {
  type = string
}

variable "private_subnet_id" {
  type = string
}

variable "ssh_ingress_cidr" {
  type = string
}

variable "wireguard_ingress_cidr" {
  type = string
}

variable "wireguard_vpn_cidr" {
  type = string
}

variable "instance_wireguard" {
  type = string
}

variable "instance_master" {
  type = string
}

variable "instance_workers" {
  type = string
}

variable "root_volume_size_gb" {
  type = number
}

variable "secrets_manager_arns" {
  type        = list(string)
  description = "Secrets Manager ARNs EC2 nodes may read"
  default     = []
}
