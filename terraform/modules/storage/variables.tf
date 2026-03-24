variable "project_id" {
  description = "GCP project ID"
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

variable "kms_key_rotation_period" {
  description = "Rotation period for the CMEK crypto key (e.g. 7776000s = 90 days)"
  type        = string
  default     = "7776000s"
}

variable "chunker_service_url" {
  description = "HTTPS URL of the rag-chunker Cloud Run service (push subscription endpoint)"
  type        = string
}

variable "chunker_service_account_email" {
  description = "Service account email used by the Pub/Sub push subscription to authenticate to the chunker"
  type        = string
}

variable "pubsub_ack_deadline_seconds" {
  description = "Pub/Sub push subscription acknowledgement deadline in seconds"
  type        = number
  default     = 300
}
