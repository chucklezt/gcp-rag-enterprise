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

variable "vpc_cidr" {
  description = "Primary subnet CIDR"
  type        = string
}

variable "vpc_connector_cidr" {
  description = "/28 CIDR for the Serverless VPC Access connector"
  type        = string
}

variable "labels" {
  description = "Common resource labels"
  type        = map(string)
  default     = {}
}
