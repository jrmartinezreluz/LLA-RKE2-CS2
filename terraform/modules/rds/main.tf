terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

resource "random_password" "master" {
  length  = 32
  special = false
}

resource "random_password" "env" {
  for_each = toset(var.environments)

  length  = 32
  special = false
}

data "aws_subnet" "primary" {
  id = var.private_subnet_id
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  rds_secondary_az = [
    for az in data.aws_availability_zones.available.names : az
    if az != data.aws_subnet.primary.availability_zone
  ][0]
}

# RDS requires subnets in at least two AZs (cluster VPC stays single-AZ for nodes).
resource "aws_subnet" "rds_secondary" {
  vpc_id            = var.vpc_id
  cidr_block        = var.rds_secondary_subnet_cidr
  availability_zone = local.rds_secondary_az

  tags = {
    Name    = "${var.project}-private-rds-${local.rds_secondary_az}"
    Project = var.project
    Role    = "rds"
  }
}

resource "aws_route_table_association" "rds_secondary" {
  subnet_id      = aws_subnet.rds_secondary.id
  route_table_id = var.private_route_table_id
}

resource "aws_db_subnet_group" "erpnext" {
  name       = "${var.project}-erpnext"
  subnet_ids = [var.private_subnet_id, aws_subnet.rds_secondary.id]

  tags = {
    Name    = "${var.project}-erpnext"
    Project = var.project
  }
}

resource "aws_security_group" "erpnext_rds" {
  name        = "${var.project}-erpnext-rds-sg"
  description = "MariaDB for ERPNext (workers only)"
  vpc_id      = var.vpc_id

  ingress {
    description     = "MariaDB from RKE2 workers"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [var.worker_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project}-erpnext-rds-sg"
    Project = var.project
  }
}

resource "aws_db_instance" "erpnext" {
  identifier = "${var.project}-erpnext"

  engine         = "mariadb"
  engine_version = "10.11"
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage_gb
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "${replace(var.database_name_prefix, "-", "_")}_prod"
  username = "erpnext_admin"
  password = random_password.master.result

  db_subnet_group_name   = aws_db_subnet_group.erpnext.name
  vpc_security_group_ids = [aws_security_group.erpnext_rds.id]

  publicly_accessible = false
  multi_az            = false

  backup_retention_period = 0
  skip_final_snapshot     = true
  deletion_protection     = false

  auto_minor_version_upgrade = true
  apply_immediately          = true

  tags = {
    Name    = "${var.project}-erpnext"
    Project = var.project
  }
}

resource "aws_secretsmanager_secret" "rds_master" {
  name                    = "${var.project}/erpnext/rds-master"
  description             = "ERPNext RDS master credentials"
  recovery_window_in_days = var.secrets_recovery_window_days

  tags = {
    Name    = "${var.project}/erpnext/rds-master"
    Project = var.project
  }
}

resource "aws_secretsmanager_secret_version" "rds_master" {
  secret_id = aws_secretsmanager_secret.rds_master.id
  secret_string = jsonencode({
    host     = aws_db_instance.erpnext.address
    port     = aws_db_instance.erpnext.port
    username = aws_db_instance.erpnext.username
    password = random_password.master.result
    engine   = "mariadb"
  })
}

resource "aws_secretsmanager_secret" "env_db" {
  for_each = toset(var.environments)

  name                    = "${var.project}/erpnext/${each.key}/db"
  description             = "ERPNext ${each.key} database connection"
  recovery_window_in_days = var.secrets_recovery_window_days

  tags = {
    Name        = "${var.project}/erpnext/${each.key}/db"
    Project     = var.project
    Environment = each.key
  }
}

resource "aws_secretsmanager_secret_version" "env_db" {
  for_each = toset(var.environments)

  secret_id = aws_secretsmanager_secret.env_db[each.key].id
  secret_string = jsonencode({
    host     = aws_db_instance.erpnext.address
    port     = aws_db_instance.erpnext.port
    database = "${replace(var.database_name_prefix, "-", "_")}_${each.key}"
    username = "${replace(var.database_name_prefix, "-", "_")}_${each.key}"
    password = random_password.env[each.key].result
    engine   = "mariadb"
  })
}

resource "aws_secretsmanager_secret" "env_admin" {
  for_each = toset(var.environments)

  name                    = "${var.project}/erpnext/${each.key}/admin"
  description             = "ERPNext ${each.key} site admin password"
  recovery_window_in_days = var.secrets_recovery_window_days

  tags = {
    Name        = "${var.project}/erpnext/${each.key}/admin"
    Project     = var.project
    Environment = each.key
  }
}

resource "aws_secretsmanager_secret_version" "env_admin" {
  for_each = toset(var.environments)

  secret_id     = aws_secretsmanager_secret.env_admin[each.key].id
  secret_string = random_password.env[each.key].result

  lifecycle {
    ignore_changes = [secret_string]
  }
}
