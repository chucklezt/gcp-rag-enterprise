locals {
  chunker_url = "https://rag-chunker-${var.project_number}.${var.region}.run.app"
}

# ── rag-chunker Cloud Run service ───────────────────────────────────────────
# Triggered by Pub/Sub push subscription on GCS finalize events.
# Reads documents from GCS, chunks with LangChain, embeds via text-embedding-004,
# upserts vectors to Vertex AI Vector Search.

resource "google_cloud_run_v2_service" "rag_chunker" {
  name     = "rag-chunker"
  location = var.region
  project  = var.project_id

  # Pub/Sub push delivery originates from Google's external infrastructure,
  # so the chunker must accept external traffic. Auth is enforced via OIDC token.
  ingress = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = var.chunker_sa_email

    vpc_access {
      connector = var.vpc_connector_id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }

    containers {
      image = var.chunker_image

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }

      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }

      env {
        name  = "REGION"
        value = var.region
      }

      env {
        name  = "BUCKET_NAME"
        value = var.bucket_name
      }

      env {
        name = "VECTOR_SEARCH_INDEX_ID"
        value_source {
          secret_key_ref {
            secret  = var.secret_vector_search_index_id
            version = "latest"
          }
        }
      }

      env {
        name = "VECTOR_SEARCH_INDEX_ENDPOINT_ID"
        value_source {
          secret_key_ref {
            secret  = var.secret_vector_search_index_endpoint_id
            version = "latest"
          }
        }
      }
    }
  }

  labels = var.labels
}

# ── rag-query-api Cloud Run service ────────────────────────────────────────
# FastAPI service handling RAG queries. VPC-internal only — the Next.js
# frontend calls it through the VPC connector.

resource "google_cloud_run_v2_service" "rag_query_api" {
  name     = "rag-query-api"
  location = var.region
  project  = var.project_id

  ingress = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = var.query_api_sa_email

    vpc_access {
      connector = var.vpc_connector_id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }

    containers {
      image = var.query_api_image

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }

      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }

      env {
        name  = "REGION"
        value = var.region
      }

      env {
        name = "VECTOR_SEARCH_INDEX_ID"
        value_source {
          secret_key_ref {
            secret  = var.secret_vector_search_index_id
            version = "latest"
          }
        }
      }

      env {
        name = "VECTOR_SEARCH_INDEX_ENDPOINT_ID"
        value_source {
          secret_key_ref {
            secret  = var.secret_vector_search_index_endpoint_id
            version = "latest"
          }
        }
      }
    }
  }

  labels = var.labels
}

# ── IAM: Pub/Sub service agent → rag-chunker invoker ──────────────────────
# Tightens the project-level run.invoker binding (from the security module)
# down to just the rag-chunker service. The Pub/Sub service agent signs
# OIDC tokens for push delivery.

# TODO: Replace allUsers with IAP-based auth before any production use.
# Temporary dev/demo exception — allows unauthenticated access to the query API.
resource "google_cloud_run_v2_service_iam_member" "query_api_public_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.rag_query_api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_v2_service_iam_member" "pubsub_sa_invoke_chunker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.rag_chunker.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:service-${var.project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

# ── Pub/Sub Push Subscription → rag-chunker ──────────────────────────────
# Wired directly to the chunker service URI — no placeholder variables needed.
# Uses OIDC auth so Cloud Run can verify the caller is Pub/Sub.

# chunker-sa needs subscriber role on the push subscription
resource "google_pubsub_subscription_iam_member" "chunker_sa_pubsub_subscriber" {
  project      = var.project_id
  subscription = google_pubsub_subscription.rag_ingest_push.name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${var.chunker_sa_email}"
}

resource "google_pubsub_subscription" "rag_ingest_push" {
  name    = "rag-ingest-push"
  topic   = var.pubsub_topic_name
  project = var.project_id
  labels  = var.labels

  ack_deadline_seconds       = 300
  message_retention_duration = "86400s"
  retain_acked_messages      = false

  push_config {
    push_endpoint = local.chunker_url

    oidc_token {
      service_account_email = var.chunker_sa_email
      audience              = local.chunker_url
    }
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "300s"
  }

  expiration_policy {
    ttl = "" # Never expire
  }
}
