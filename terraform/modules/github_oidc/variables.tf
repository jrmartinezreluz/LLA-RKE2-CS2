variable "project" {
  type = string
}

variable "github_org" {
  type        = string
  description = "GitHub org or user that owns erpnext-app"
}

variable "github_repo" {
  type        = string
  default     = "erpnext-app"
  description = "Repository allowed to assume the ECR push role"
}

variable "ecr_repository_arns" {
  type        = list(string)
  description = "ECR repository ARNs the role may push to"
}

variable "create_oidc_provider" {
  type        = bool
  default     = true
  description = "Create GitHub OIDC provider (set false if already exists in the account)"
}
