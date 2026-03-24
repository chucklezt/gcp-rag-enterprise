locals {
  common_labels = {
    project = "enterprise-rag-gcp"
    owner   = "chuck-tsocanos"
    env     = var.environment
  }
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
