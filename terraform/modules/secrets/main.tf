locals {
  secret_names = {
    rke2_cluster_token   = "${var.project}/rke2/cluster-token"
    grafana_admin          = "${var.project}/monitoring/grafana-admin"
    alertmanager_webhook   = "${var.project}/monitoring/alertmanager-webhook"
    argocd_admin           = "${var.project}/argocd/admin-password"
    argocd_github_app      = "${var.project}/argocd/github-app"
    eso_credentials        = "${var.project}/bootstrap/eso-iam-credentials"
  }

  # Wildcard covers app secrets (n8n, erpnext, hotel, …) without listing each ARN.
  eso_secret_arn = "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${var.project}/*"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

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
        Resource = concat(
          [local.eso_secret_arn],
          var.additional_secret_arns
        )
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
