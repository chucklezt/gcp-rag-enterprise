resource "google_vertex_ai_index" "rag_index" {
  project      = var.project_id
  region       = var.region
  display_name = "rag-embeddings-${var.environment}"
  description  = "Vertex AI Vector Search index for RAG document embeddings"

  metadata {
    contents_delta_uri = "gs://${var.project_id}-rag-documents/vector-index/"

    config {
      dimensions                  = var.dimensions
      shard_size                  = var.shard_size
      approximate_neighbors_count = var.approximate_neighbors_count
      distance_measure_type       = "DOT_PRODUCT_DISTANCE"

      algorithm_config {
        tree_ah_config {
          leaf_node_embedding_count    = 1000
          leaf_nodes_to_search_percent = 10
        }
      }
    }
  }

  index_update_method = "STREAM_UPDATE"

  labels = var.labels
}

resource "google_vertex_ai_index_endpoint" "rag_endpoint" {
  project      = var.project_id
  region       = var.region
  display_name = "rag-endpoint-${var.environment}"
  description  = "VPC-peered endpoint for RAG vector search queries"
  network      = "projects/${var.project_number}/global/networks/rag-vpc-${var.environment}"

  labels = var.labels
}
