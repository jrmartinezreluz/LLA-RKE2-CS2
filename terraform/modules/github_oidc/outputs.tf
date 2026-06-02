output "role_arn" {
  value       = aws_iam_role.erpnext_github_actions.arn
  description = "Set as AWS_ROLE_ARN secret in erpnext-app GitHub repo"
}

output "role_name" {
  value = aws_iam_role.erpnext_github_actions.name
}
