variable "project" {
  type = string
}

variable "repositories" {
  description = "ECR repository suffixes (full name: project/suffix)"
  type        = list(string)
  default     = ["erpnext"]
}
