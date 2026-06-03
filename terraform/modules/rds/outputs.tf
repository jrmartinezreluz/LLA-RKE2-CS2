output "endpoint" {
  value = aws_db_instance.erpnext.address
}

output "port" {
  value = aws_db_instance.erpnext.port
}

output "secret_arns" {
  value = concat(
    [aws_secretsmanager_secret.rds_master.arn],
    [for s in aws_secretsmanager_secret.env_db : s.arn],
    [for s in aws_secretsmanager_secret.env_admin : s.arn]
  )
}

output "env_db_secret_names" {
  value = { for k, s in aws_secretsmanager_secret.env_db : k => s.name }
}

output "env_admin_secret_names" {
  value = { for k, s in aws_secretsmanager_secret.env_admin : k => s.name }
}
