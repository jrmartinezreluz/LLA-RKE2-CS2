locals {
  secret_names = {
    rke2_cluster_token = "${var.project}/rke2/cluster-token"
    grafana_admin      = "${var.project}/monitoring/grafana-admin"
    argocd_admin       = "${var.project}/argocd/admin-password"
    eso_credentials    = "${var.project}/bootstrap/eso-iam-credentials"
  }
}

resource "aws_secretsmanager_secret" "this" {
  for_each = local.secret_names

  name                    = each.value
  description             = "LLA-RKE2-CS2 ${each.key} — set value in AWS Console or CLI"
  recovery_window_in_days = var.recovery_window_in_days

  tags = {
    Name    = each.value
    Project = var.project
  }
}

resource "aws_secretsmanager_secret_version" "placeholder" {
  for_each = { for k, v in local.secret_names : k => v if k != "eso_credentials" }

  secret_id     = aws_secretsmanager_secret.this[each.key].id
  secret_string = "CHANGE_ME"

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# IAM user for External Secrets Operator (Kubernetes pods)
resource "aws_iam_user" "external_secrets" {
  name = "${var.project}-external-secrets"

  tags = {
    Name = "${var.project}-external-secrets"
  }
}

resource "aws_iam_access_key" "external_secrets" {
  user = aws_iam_user.external_secrets.name
}

resource "aws_iam_user_policy" "external_secrets" {
  name = "${var.project}-external-secrets-read"
  user = aws_iam_user.external_secrets.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadProjectSecrets"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = [for s in aws_secretsmanager_secret.this : s.arn]
      }
    ]
  })
}

resource "aws_secretsmanager_secret_version" "eso_credentials" {
  secret_id = aws_secretsmanager_secret.this["eso_credentials"].id
  secret_string = jsonencode({
    access_key_id     = aws_iam_access_key.external_secrets.id
    secret_access_key = aws_iam_access_key.external_secrets.secret
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}
