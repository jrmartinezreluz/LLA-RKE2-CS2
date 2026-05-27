resource "aws_security_group" "wireguard" {
  name        = "${var.project}-wireguard-sg"
  description = "WireGuard VPN endpoint"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from admin CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_ingress_cidr]
  }

  ingress {
    description = "WireGuard"
    from_port   = 51820
    to_port     = 51820
    protocol    = "udp"
    cidr_blocks = [var.wireguard_ingress_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-wireguard-sg"
  }
}

resource "aws_security_group" "master" {
  name        = "${var.project}-master-sg"
  description = "RKE2 control plane"
  vpc_id      = var.vpc_id

  ingress {
    description     = "SSH from WireGuard instance"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.wireguard.id]
  }

  ingress {
    description = "SSH from VPN clients"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.wireguard_vpn_cidr]
  }

  ingress {
    description = "Cluster traffic between nodes"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  ingress {
    description = "Cluster traffic from workers (VPC CIDR)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description     = "Kubernetes API from WireGuard"
    from_port       = 6443
    to_port         = 6443
    protocol        = "tcp"
    security_groups = [aws_security_group.wireguard.id]
  }

  ingress {
    description     = "RKE2 join from WireGuard"
    from_port       = 9345
    to_port         = 9345
    protocol        = "tcp"
    security_groups = [aws_security_group.wireguard.id]
  }

  ingress {
    description     = "Node metrics from workers (Prometheus)"
    from_port       = 9100
    to_port         = 9100
    protocol        = "tcp"
    security_groups = [aws_security_group.worker.id]
  }

  ingress {
    description = "Kubernetes API from VPN"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.wireguard_vpn_cidr]
  }

  ingress {
    description = "RKE2 join from VPN"
    from_port   = 9345
    to_port     = 9345
    protocol    = "tcp"
    cidr_blocks = [var.wireguard_vpn_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-master-sg"
  }
}

resource "aws_security_group" "worker" {
  name        = "${var.project}-worker-sg"
  description = "RKE2 workers and workloads"
  vpc_id      = var.vpc_id

  ingress {
    description     = "SSH from WireGuard instance"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.wireguard.id]
  }

  ingress {
    description = "SSH from VPN clients"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.wireguard_vpn_cidr]
  }

  ingress {
    description = "Cluster traffic between workers"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  ingress {
    description = "Cluster traffic from master (VPC CIDR)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Node metrics from VPC (Prometheus scrapes)"
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-worker-sg"
  }
}

locals {
  private_instances = {
    master1 = {
      type = var.instance_master
      role = "master"
      sg   = aws_security_group.master.id
    }
    worker1 = {
      type = var.instance_workers
      role = "worker"
      sg   = aws_security_group.worker.id
    }
    worker2 = {
      type = var.instance_workers
      role = "worker"
      sg   = aws_security_group.worker.id
    }
    worker3 = {
      type = var.instance_workers
      role = "worker"
      sg   = aws_security_group.worker.id
    }
  }

  ec2_common_metadata = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }
}

resource "aws_instance" "wireguard" {
  ami                         = var.ami_id
  instance_type               = var.instance_wireguard
  subnet_id                   = var.public_subnet_id
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.wireguard.id]
  associate_public_ip_address = true

  metadata_options {
    http_endpoint               = local.ec2_common_metadata.http_endpoint
    http_tokens                 = local.ec2_common_metadata.http_tokens
    http_put_response_hop_limit = local.ec2_common_metadata.http_put_response_hop_limit
    instance_metadata_tags      = local.ec2_common_metadata.instance_metadata_tags
  }

  root_block_device {
    volume_size           = var.root_volume_size_gb
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = "wireguard"
    Role = "wireguard"
  }
}

resource "aws_eip" "wireguard" {
  domain = "vpc"

  tags = {
    Name = "${var.project}-wireguard-eip"
  }
}

resource "aws_eip_association" "wireguard" {
  instance_id   = aws_instance.wireguard.id
  allocation_id = aws_eip.wireguard.id
}

resource "aws_instance" "private" {
  for_each = local.private_instances

  ami                         = var.ami_id
  instance_type               = each.value.type
  subnet_id                   = var.private_subnet_id
  key_name                    = var.key_name
  vpc_security_group_ids      = [each.value.sg]
  iam_instance_profile        = aws_iam_instance_profile.rke2_node.name

  metadata_options {
    http_endpoint               = local.ec2_common_metadata.http_endpoint
    http_tokens                 = local.ec2_common_metadata.http_tokens
    http_put_response_hop_limit = local.ec2_common_metadata.http_put_response_hop_limit
    instance_metadata_tags      = local.ec2_common_metadata.instance_metadata_tags
  }

  root_block_device {
    volume_size           = var.root_volume_size_gb
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = each.key
    Role = each.value.role
  }
}
