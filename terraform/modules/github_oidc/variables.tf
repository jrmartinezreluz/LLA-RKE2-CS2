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

variable "hotel_github_repo" {
  type        = string
  default     = "hotel-app"
  description = "Repository allowed to assume the hotel ECR push role"
}

variable "hotel_github_org" {
  type        = string
  default     = "jrmartinezreluz"
  description = "GitHub org or user that owns hotel-app"
}

variable "hotel_ecr_repository_arns" {
  type        = list(string)
  default     = []
  description = "ECR repository ARNs hotel-app GitHub Actions may push to"
}
