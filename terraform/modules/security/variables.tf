variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "project_number" {
  description = "GCP project number (used for service agent identities)"
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

variable "billing_account_id" {
  description = "GCP billing account ID (format: XXXXXX-XXXXXX-XXXXXX)"
  type        = string
}

variable "budget_alert_email" {
  description = "Email address to notify on budget threshold alerts"
  type        = string
}

# Passed from storage module outputs
variable "bucket_name" {
  description = "Name of the RAG documents GCS bucket"
  type        = string
}

variable "kms_crypto_key_id" {
  description = "ID of the CMEK crypto key (for Secret Manager CMEK if desired)"
  type        = string
}
