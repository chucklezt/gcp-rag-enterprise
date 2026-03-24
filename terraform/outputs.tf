output "vpc_network_id" {
  description = "Self-link of the RAG VPC network"
  value       = module.networking.network_id
}

output "vpc_subnet_id" {
  description = "Self-link of the primary RAG subnet"
  value       = module.networking.subnet_id
}

output "vpc_connector_id" {
  description = "ID of the Serverless VPC Access connector"
  value       = module.networking.vpc_connector_id
}

output "bucket_name" {
  description = "Name of the RAG documents GCS bucket"
  value       = module.storage.bucket_name
}

output "kms_crypto_key_id" {
  description = "ID of the CMEK crypto key"
  value       = module.storage.kms_crypto_key_id
}

output "pubsub_topic_id" {
  description = "ID of the rag-ingest-trigger Pub/Sub topic"
  value       = module.storage.pubsub_topic_id
}

output "pubsub_subscription_id" {
  description = "ID of the rag-ingest-push Pub/Sub subscription"
  value       = module.storage.pubsub_subscription_id
}

output "chunker_sa_email" {
  description = "Email of the chunker-sa service account"
  value       = module.security.chunker_sa_email
}

output "query_api_sa_email" {
  description = "Email of the query-api-sa service account"
  value       = module.security.query_api_sa_email
}

output "artifact_registry_repository_url" {
  description = "Docker push/pull URL for the rag-docker Artifact Registry repository"
  value       = module.security.artifact_registry_repository_url
}
