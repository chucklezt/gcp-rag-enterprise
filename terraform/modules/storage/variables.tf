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

