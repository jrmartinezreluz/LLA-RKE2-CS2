variable "project" {
  type = string
}

variable "recovery_window_in_days" {
  type    = number
  default = 7
}

variable "additional_secret_arns" {
  description = "Extra Secrets Manager ARNs readable by External Secrets Operator"
  type        = list(string)
  default     = []
}
