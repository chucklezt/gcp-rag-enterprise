output "chunker_service_name" {
  description = "Name of the rag-chunker Cloud Run service"
  value       = google_cloud_run_v2_service.rag_chunker.name
}

output "chunker_service_url" {
  description = "HTTPS URL of the rag-chunker Cloud Run service"
  value       = google_cloud_run_v2_service.rag_chunker.uri
}

output "query_api_service_name" {
  description = "Name of the rag-query-api Cloud Run service"
  value       = google_cloud_run_v2_service.rag_query_api.name
}

output "query_api_service_url" {
  description = "HTTPS URL of the rag-query-api Cloud Run service"
  value       = google_cloud_run_v2_service.rag_query_api.uri
}

output "pubsub_subscription_id" {
  description = "ID of the rag-ingest-push Pub/Sub subscription"
  value       = google_pubsub_subscription.rag_ingest_push.id
}
