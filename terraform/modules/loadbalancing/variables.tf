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

variable "internal_domain" {
  type        = string
  description = "Private Route53 zone name (e.g. lla.internal)"
}

variable "master_instance_id" {
  type = string
}

variable "worker_instance_id_map" {
  type = map(string)
}

variable "master_security_group_id" {
  type = string
}

variable "worker_security_group_id" {
  type = string
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
  type        = bool
  description = "Create *.internal_domain alias to ingress NLB for Traefik host rules"
  default     = true
}

variable "argocd_record_name" {
  type    = string
  default = "argocd"
}

variable "grafana_record_name" {
  type    = string
  default = "grafana"
}
