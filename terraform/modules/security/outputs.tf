output "chunker_sa_email" {
  description = "Email of the chunker-sa service account"
  value       = google_service_account.chunker_sa.email
}

output "chunker_sa_member" {
  description = "IAM member string for chunker-sa (serviceAccount:...)"
  value       = google_service_account.chunker_sa.member
}

output "query_api_sa_email" {
  description = "Email of the query-api-sa service account"
  value       = google_service_account.query_api_sa.email
}

output "query_api_sa_member" {
  description = "IAM member string for query-api-sa (serviceAccount:...)"
  value       = google_service_account.query_api_sa.member
}

output "cloudbuild_sa_email" {
  description = "Email of the cloudbuild-sa service account"
  value       = google_service_account.cloudbuild_sa.email
}

output "artifact_registry_repository_id" {
  description = "Full resource ID of the rag-docker Artifact Registry repository"
  value       = google_artifact_registry_repository.rag_docker.id
}

output "artifact_registry_repository_url" {
  description = "Docker pull/push URL for the rag-docker repository"
  value       = "${google_artifact_registry_repository.rag_docker.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.rag_docker.name}"
}

output "secret_vector_search_index_id" {
  description = "Secret Manager secret ID for the Vector Search index ID"
  value       = google_secret_manager_secret.vector_search_index_id.secret_id
}

output "secret_vector_search_index_endpoint_id" {
  description = "Secret Manager secret ID for the Vector Search index endpoint ID"
  value       = google_secret_manager_secret.vector_search_index_endpoint_id.secret_id
}

output "budget_alerts_topic_id" {
  description = "ID of the Pub/Sub topic receiving billing budget alerts"
  value       = google_pubsub_topic.budget_alerts.id
}
