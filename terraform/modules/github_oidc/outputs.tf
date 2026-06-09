output "role_arn" {
  value       = aws_iam_role.erpnext_github_actions.arn
  description = "Set as AWS_ROLE_ARN secret in erpnext-app GitHub repo"
}

output "role_name" {
  value = aws_iam_role.erpnext_github_actions.name
}

output "hotel_role_arn" {
  value       = length(var.hotel_ecr_repository_arns) > 0 ? aws_iam_role.hotel_github_actions[0].arn : null
  description = "Set as AWS_ROLE_ARN secret in hotel-app GitHub repo"
}

output "hotel_role_name" {
  value = length(var.hotel_ecr_repository_arns) > 0 ? aws_iam_role.hotel_github_actions[0].name : null
}
