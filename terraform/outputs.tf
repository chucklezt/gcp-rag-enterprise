output "vpc_network_id" {
  description = "Self-link of the RAG VPC network"
  value       = module.networking.network_id
}

output "vpc_subnet_id" {
  description = "Self-link of the primary RAG subnet"
  value       = module.networking.subnet_id
}

output "vpc_connector_id" {
  description = "ID of the Serverless VPC Access connector"
  value       = module.networking.vpc_connector_id
}
