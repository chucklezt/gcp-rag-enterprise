variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "project_number" {
  description = "GCP project number (used for Pub/Sub service agent IAM)"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, prod)"
  type        = string
}

variable "labels" {
  description = "Common resource labels"
  type        = map(string)
  default     = {}
}

# ── Networking ──────────────────────────────────────────────────────────────

variable "vpc_connector_id" {
  description = "Full ID of the Serverless VPC Access connector"
  type        = string
}

# ── Service Accounts ────────────────────────────────────────────────────────

variable "chunker_sa_email" {
  description = "Email of the chunker-sa service account"
  type        = string
}

variable "query_api_sa_email" {
  description = "Email of the query-api-sa service account"
  type        = string
}

# ── Container images ────────────────────────────────────────────────────────

variable "chunker_image" {
  description = "Full Artifact Registry image URL for rag-chunker"
  type        = string
}

variable "query_api_image" {
  description = "Full Artifact Registry image URL for rag-query-api"
  type        = string
}

# ── Storage / Pub/Sub ───────────────────────────────────────────────────────

variable "bucket_name" {
  description = "Name of the RAG documents GCS bucket"
  type        = string
}

variable "pubsub_topic_name" {
  description = "Name of the rag-ingest-trigger Pub/Sub topic"
  type        = string
}

# ── Secret Manager ──────────────────────────────────────────────────────────

variable "secret_vector_search_index_id" {
  description = "Secret Manager secret ID for the Vector Search index ID"
  type        = string
}

variable "secret_vector_search_index_endpoint_id" {
  description = "Secret Manager secret ID for the Vector Search index endpoint ID"
  type        = string
}
