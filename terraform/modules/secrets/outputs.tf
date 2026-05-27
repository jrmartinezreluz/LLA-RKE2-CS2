output "secret_arns" {
  value = [for s in aws_secretsmanager_secret.this : s.arn]
}

output "secret_names" {
  value = { for k, s in aws_secretsmanager_secret.this : k => s.name }
}

output "eso_credentials_secret_name" {
  value = aws_secretsmanager_secret.this["eso_credentials"].name
}
