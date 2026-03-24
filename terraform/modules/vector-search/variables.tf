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

variable "project_number" {
  description = "GCP project number (required for Vertex AI network format)"
  type        = string
}

variable "labels" {
  description = "Common resource labels"
  type        = map(string)
  default     = {}
}

variable "dimensions" {
  description = "Embedding vector dimensionality"
  type        = number
  default     = 768
}

variable "shard_size" {
  description = "Index shard size (SHARD_SIZE_SMALL, SHARD_SIZE_MEDIUM, SHARD_SIZE_LARGE)"
  type        = string
  default     = "SHARD_SIZE_SMALL"
}

variable "approximate_neighbors_count" {
  description = "Number of approximate neighbors to return during query"
  type        = number
  default     = 5
}
