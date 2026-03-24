output "kms_key_ring_id" {
  description = "ID of the KMS key ring"
  value       = google_kms_key_ring.rag_keyring.id
}

output "kms_crypto_key_id" {
  description = "ID of the CMEK crypto key"
  value       = google_kms_crypto_key.rag_storage_key.id
}

output "bucket_name" {
  description = "Name of the RAG documents GCS bucket"
  value       = google_storage_bucket.rag_documents.name
}

output "bucket_url" {
  description = "gs:// URL of the RAG documents bucket"
  value       = google_storage_bucket.rag_documents.url
}

output "pubsub_topic_id" {
  description = "ID of the rag-ingest-trigger Pub/Sub topic"
  value       = google_pubsub_topic.rag_ingest_trigger.id
}

output "pubsub_topic_name" {
  description = "Name of the rag-ingest-trigger Pub/Sub topic"
  value       = google_pubsub_topic.rag_ingest_trigger.name
}

output "pubsub_subscription_id" {
  description = "ID of the rag-ingest-push Pub/Sub subscription"
  value       = google_pubsub_subscription.rag_ingest_push.id
}
