variable "project" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_id" {
  type = string
}

variable "private_route_table_id" {
  description = "Route table for the primary private subnet (secondary RDS subnet is associated here too)"
  type        = string
}

variable "rds_secondary_subnet_cidr" {
  description = "Extra private subnet in a second AZ — required by RDS subnet groups"
  type        = string
  default     = "10.0.12.0/24"
}

variable "worker_security_group_id" {
  type = string
}

variable "instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "allocated_storage_gb" {
  type    = number
  default = 20
}

variable "database_name_prefix" {
  type    = string
  default = "erpnext"
}

variable "environments" {
  description = "Logical ERPNext environments sharing this RDS instance"
  type        = list(string)
  default     = ["dev", "stg", "prod"]
}

variable "secrets_recovery_window_days" {
  type    = number
  default = 7
}
