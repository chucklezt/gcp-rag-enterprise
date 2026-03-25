output "network_id" {
  description = "Self-link of the RAG VPC network"
  value       = google_compute_network.rag_vpc.self_link
}

output "network_name" {
  description = "Name of the RAG VPC network"
  value       = google_compute_network.rag_vpc.name
}

output "subnet_id" {
  description = "Self-link of the primary RAG subnet"
  value       = google_compute_subnetwork.rag_subnet.self_link
}

output "subnet_name" {
  description = "Name of the primary RAG subnet"
  value       = google_compute_subnetwork.rag_subnet.name
}

output "router_name" {
  description = "Name of the Cloud Router"
  value       = google_compute_router.rag_router.name
}

output "vpc_connector_id" {
  description = "Full ID of the Serverless VPC Access connector"
  value       = google_vpc_access_connector.rag_connector.id
}

output "vpc_connector_name" {
  description = "Name of the Serverless VPC Access connector"
  value       = google_vpc_access_connector.rag_connector.name
}

output "private_service_connection_peering" {
  description = "Peering name of the private service networking connection"
  value       = google_service_networking_connection.private_service_access.peering
}
