terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
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
  additional_secret_arns  = var.enable_erpnext_rds ? module.rds[0].secret_arns : []
}

module "ecr" {
  count  = var.enable_erpnext_ecr ? 1 : 0
  source = "./modules/ecr"

  project      = var.project
  repositories = var.erpnext_ecr_repositories
}

module "github_oidc" {
  count  = var.enable_erpnext_ecr ? 1 : 0
  source = "./modules/github_oidc"

  project               = var.project
  github_org            = var.github_org
  github_repo           = var.erpnext_github_repo
  ecr_repository_arns   = values(module.ecr[0].repository_arns)
  create_oidc_provider  = var.create_github_oidc_provider
}

module "rds" {
  count  = var.enable_erpnext_rds ? 1 : 0
  source = "./modules/rds"

  project                      = var.project
  vpc_id                       = module.vpc.vpc_id
  private_subnet_id            = module.vpc.private_subnet_id
  private_route_table_id       = module.vpc.private_route_table_id
  worker_security_group_id     = module.compute.worker_security_group_id
  instance_class               = var.erpnext_rds_instance_class
  allocated_storage_gb         = var.erpnext_rds_storage_gb
  secrets_recovery_window_days = var.secrets_recovery_window_days
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
  vpn_client_cidrs = distinct(compact([
    var.wireguard_vpn_cidr,
    var.enable_client_vpn ? var.client_vpn_cidr : "",
  ]))
  instance_master        = var.instance_master
  instance_workers       = var.instance_workers
  root_volume_size_gb    = var.root_volume_size_gb
  secrets_manager_arns = concat(
    module.secrets.secret_arns,
    var.enable_erpnext_rds ? module.rds[0].secret_arns : []
  )
  ecr_repository_arns = var.enable_erpnext_ecr ? values(module.ecr[0].repository_arns) : []
}

module "client_vpn" {
  count  = var.enable_client_vpn ? 1 : 0
  source = "./modules/client_vpn"

  project             = var.project
  vpc_id              = module.vpc.vpc_id
  vpc_cidr            = module.vpc.vpc_cidr
  private_subnet_id   = module.vpc.private_subnet_id
  client_cidr_block   = var.client_vpn_cidr
  split_tunnel        = var.client_vpn_split_tunnel
  client_common_name  = var.client_vpn_client_name
  internal_domain     = var.internal_domain
  profile_output_path = abspath("${path.module}/../ansible/client-vpn.ovpn")
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
