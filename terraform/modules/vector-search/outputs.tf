output "index_id" {
  description = "ID of the Vertex AI Vector Search index"
  value       = google_vertex_ai_index.rag_index.id
}

output "index_name" {
  description = "Resource name of the Vertex AI Vector Search index"
  value       = google_vertex_ai_index.rag_index.name
}

output "index_endpoint_id" {
  description = "ID of the Vertex AI Vector Search index endpoint"
  value       = google_vertex_ai_index_endpoint.rag_endpoint.id
}

output "index_endpoint_name" {
  description = "Resource name of the Vertex AI Vector Search index endpoint"
  value       = google_vertex_ai_index_endpoint.rag_endpoint.name
}

output "deployed_index_id" {
  description = "ID of the deployed index"
  value       = google_vertex_ai_index_endpoint_deployed_index.rag_deployed_index.id
}
