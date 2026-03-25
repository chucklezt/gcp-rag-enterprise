locals {
  common_labels = {
    project = "enterprise-rag-gcp"
    owner   = "chuck-tsocanos"
    env     = var.environment
  }
}

module "security" {
  source = "./modules/security"

  project_id         = var.project_id
  project_number     = var.project_number
  region             = var.region
  environment        = var.environment
  labels             = local.common_labels
  billing_account_id = var.billing_account_id
  budget_alert_email = var.budget_alert_email
  bucket_name        = module.storage.bucket_name
  kms_crypto_key_id  = module.storage.kms_crypto_key_id
}

module "storage" {
  source = "./modules/storage"

  project_id  = var.project_id
  region      = var.region
  environment = var.environment
  labels      = local.common_labels
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

module "cloud_run" {
  source = "./modules/cloud-run"

  project_id     = var.project_id
  project_number = var.project_number
  region         = var.region
  environment    = var.environment
  labels         = local.common_labels

  vpc_connector_id   = module.networking.vpc_connector_id
  chunker_sa_email   = module.security.chunker_sa_email
  query_api_sa_email = module.security.query_api_sa_email
  chunker_image      = var.chunker_image
  query_api_image    = var.query_api_image

  bucket_name       = module.storage.bucket_name
  pubsub_topic_name = module.storage.pubsub_topic_name

  secret_vector_search_index_id          = module.security.secret_vector_search_index_id
  secret_vector_search_index_endpoint_id = module.security.secret_vector_search_index_endpoint_id
}

module "vector_search" {
  source = "./modules/vector-search"

  project_id     = var.project_id
  project_number = var.project_number
  region         = var.region
  environment    = var.environment
  labels         = local.common_labels

  # VPC peering must be established before the private endpoint can serve
  depends_on = [module.networking]
}
