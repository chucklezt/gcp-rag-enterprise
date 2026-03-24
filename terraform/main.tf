locals {
  common_labels = {
    project = "enterprise-rag-gcp"
    owner   = "chuck-tsocanos"
    env     = var.environment
  }
}

module "security" {
  source = "./modules/security"

  project_id             = var.project_id
  project_number         = var.project_number
  region                 = var.region
  environment            = var.environment
  labels                 = local.common_labels
  billing_account_id     = var.billing_account_id
  budget_alert_email     = var.budget_alert_email
  bucket_name            = module.storage.bucket_name
  pubsub_subscription_id = module.storage.pubsub_subscription_id
  kms_crypto_key_id      = module.storage.kms_crypto_key_id
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
