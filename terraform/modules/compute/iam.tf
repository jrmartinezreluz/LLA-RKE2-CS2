data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "node_secrets" {
  statement {
    sid    = "ReadProjectSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = var.secrets_manager_arns
  }

  statement {
    sid    = "DecryptSecretsManagerKms"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${var.aws_region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rke2_node" {
  name               = "${var.project}-rke2-node-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = {
    Name = "${var.project}-rke2-node-role"
  }
}

resource "aws_iam_role_policy" "node_secrets" {
  name   = "${var.project}-secrets-read"
  role   = aws_iam_role.rke2_node.id
  policy = data.aws_iam_policy_document.node_secrets.json
}

resource "aws_iam_instance_profile" "rke2_node" {
  name = "${var.project}-rke2-node-profile"
  role = aws_iam_role.rke2_node.name
}
