terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "vpc" {
  source = "./modules/vpc"

  project             = var.project
  vpc_cidr            = var.vpc_cidr
  availability_zone   = var.availability_zone
  public_subnet_cidr  = var.public_subnet_cidr
  private_subnet_cidr = var.private_subnet_cidr
}

module "secrets" {
  source = "./modules/secrets"

  project                 = var.project
  recovery_window_in_days = var.secrets_recovery_window_days
}

module "compute" {
  source = "./modules/compute"

  project                = var.project
  aws_region             = var.aws_region
  key_name               = var.key_name
  ami_id                 = var.ami_id
  vpc_id                 = module.vpc.vpc_id
  vpc_cidr               = module.vpc.vpc_cidr
  public_subnet_id       = module.vpc.public_subnet_id
  private_subnet_id      = module.vpc.private_subnet_id
  ssh_ingress_cidr       = var.ssh_ingress_cidr
  wireguard_ingress_cidr = var.wireguard_ingress_cidr
  instance_wireguard     = var.instance_wireguard
  wireguard_vpn_cidr     = var.wireguard_vpn_cidr
  instance_master        = var.instance_master
  instance_workers       = var.instance_workers
  root_volume_size_gb    = var.root_volume_size_gb
  secrets_manager_arns   = module.secrets.secret_arns
}

module "loadbalancing" {
  source = "./modules/loadbalancing"

  project                  = var.project
  vpc_id                   = module.vpc.vpc_id
  vpc_cidr                 = module.vpc.vpc_cidr
  private_subnet_id        = module.vpc.private_subnet_id
  internal_domain          = var.internal_domain
  master_instance_id       = module.compute.master_instance_id
  worker_instance_id_map   = module.compute.worker_instance_id_map
  master_security_group_id = module.compute.master_security_group_id
  worker_security_group_id = module.compute.worker_security_group_id
  api_record_name          = var.api_record_name
  join_record_name         = var.join_record_name
  ingress_record_name      = var.ingress_record_name
  wildcard_ingress         = var.wildcard_ingress
  argocd_record_name       = var.argocd_record_name
  grafana_record_name      = var.grafana_record_name
}
