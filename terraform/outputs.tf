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

output "cloudbuild_sa_email" {
  description = "Email of the cloudbuild-sa service account"
  value       = module.security.cloudbuild_sa_email
}

output "artifact_registry_repository_url" {
  description = "Docker push/pull URL for the rag-docker Artifact Registry repository"
  value       = module.security.artifact_registry_repository_url
}

output "chunker_service_url" {
  description = "HTTPS URL of the rag-chunker Cloud Run service"
  value       = module.cloud_run.chunker_service_url
}

output "query_api_service_url" {
  description = "HTTPS URL of the rag-query-api Cloud Run service"
  value       = module.cloud_run.query_api_service_url
}

output "vector_search_index_id" {
  description = "ID of the Vertex AI Vector Search index"
  value       = module.vector_search.index_id
}

output "vector_search_index_name" {
  description = "Resource name of the Vertex AI Vector Search index"
  value       = module.vector_search.index_name
}

output "vector_search_endpoint_id" {
  description = "ID of the Vertex AI Vector Search index endpoint"
  value       = module.vector_search.index_endpoint_id
}

output "vector_search_endpoint_name" {
  description = "Resource name of the Vertex AI Vector Search index endpoint"
  value       = module.vector_search.index_endpoint_name
}
