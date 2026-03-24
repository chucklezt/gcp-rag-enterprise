locals {
  common_labels = {
    project = "enterprise-rag-gcp"
    owner   = "chuck-tsocanos"
    env     = var.environment
  }
}

module "storage" {
  source = "./modules/storage"

  project_id                    = var.project_id
  region                        = var.region
  environment                   = var.environment
  labels                        = local.common_labels
  chunker_service_url           = var.chunker_service_url
  chunker_service_account_email = var.chunker_service_account_email
}

module "networking" {
  source = "./modules/networking"

  project_id         = var.project_id
  region             = var.region
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  vpc_connector_cidr = var.vpc_connector_cidr
  labels             = local.common_labels
}
