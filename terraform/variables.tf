variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "Primary GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Primary GCP zone"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Deployment environment (dev, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be 'dev' or 'prod'."
  }
}

variable "vpc_cidr" {
  description = "Primary subnet CIDR for the RAG VPC"
  type        = string
  default     = "10.10.0.0/24"
}

variable "chunker_service_url" {
  description = "HTTPS URL of the rag-chunker Cloud Run service (set after cloud-run module is applied)"
  type        = string
  default     = "https://placeholder.invalid" # Replaced once rag-chunker is deployed
}

variable "chunker_service_account_email" {
  description = "Email of the chunker-sa service account (set after security module is applied)"
  type        = string
  default     = "" # Replaced once security module is applied
}

variable "vpc_connector_cidr" {
  description = "/28 CIDR reserved for the Serverless VPC Access connector"
  type        = string
  default     = "10.10.1.0/28"
}
