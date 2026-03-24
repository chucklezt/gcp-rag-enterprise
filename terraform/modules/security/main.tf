# ── Service Accounts ─────────────────────────────────────────────────────────

resource "google_service_account" "chunker_sa" {
  account_id   = "chunker-sa"
  display_name = "RAG Chunker Service Account"
  description  = "Identity for the rag-chunker Cloud Run service"
  project      = var.project_id
}

resource "google_service_account" "query_api_sa" {
  account_id   = "query-api-sa"
  display_name = "RAG Query API Service Account"
  description  = "Identity for the rag-query-api Cloud Run service"
  project      = var.project_id
}

# ── Cloud Build service account ──────────────────────────────────────────────

resource "google_service_account" "cloudbuild_sa" {
  account_id   = "cloudbuild-sa"
  display_name = "Cloud Build Service Account"
  description  = "Dedicated identity for Cloud Build CI/CD pipeline"
  project      = var.project_id
}

locals {
  cloudbuild_project_roles = [
    "roles/cloudbuild.builds.builder",
    "roles/run.developer",
    "roles/iam.serviceAccountUser",
    "roles/artifactregistry.writer",
    "roles/logging.logWriter",
    "roles/storage.objectAdmin",
  ]
}

resource "google_project_iam_member" "cloudbuild_sa_project_roles" {
  for_each = toset(local.cloudbuild_project_roles)

  project = var.project_id
  role    = each.value
  member  = google_service_account.cloudbuild_sa.member
}

# ── chunker-sa: project-level roles ──────────────────────────────────────────

locals {
  chunker_project_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudtrace.agent",
    "roles/aiplatform.user", # text-embedding-004 + Vector Search upsert
  ]

  query_api_project_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudtrace.agent",
    "roles/aiplatform.user", # text-embedding-004 + Vector Search query + Gemini
  ]
}

resource "google_project_iam_member" "chunker_sa_project_roles" {
  for_each = toset(local.chunker_project_roles)

  project = var.project_id
  role    = each.value
  member  = google_service_account.chunker_sa.member
}

resource "google_project_iam_member" "query_api_sa_project_roles" {
  for_each = toset(local.query_api_project_roles)

  project = var.project_id
  role    = each.value
  member  = google_service_account.query_api_sa.member
}

# ── chunker-sa: resource-scoped roles ────────────────────────────────────────

# Read uploaded documents from GCS — objectViewer is sufficient, chunker never writes back
resource "google_storage_bucket_iam_member" "chunker_sa_gcs_reader" {
  bucket = var.bucket_name
  role   = "roles/storage.objectViewer"
  member = google_service_account.chunker_sa.member
}

# ── Pub/Sub service agent → chunker Cloud Run invoker ─────────────────────────
# Pub/Sub must present a valid OIDC token when pushing to the chunker endpoint.
# The Pub/Sub service agent is the identity that signs the token; it must have
# run.invoker so Cloud Run accepts it. Binding is at project scope because the
# Cloud Run service resource doesn't exist yet — tighten to service level in
# the cloud-run module once the service is created.

# Pub/Sub service agent needs to mint OIDC tokens as chunker-sa for push delivery
resource "google_service_account_iam_member" "pubsub_sa_token_creator_chunker" {
  service_account_id = google_service_account.chunker_sa.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${var.project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "pubsub_sa_run_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:service-${var.project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

# ── Secret Manager secrets ────────────────────────────────────────────────────
# Secrets are created here as empty shells; values are populated out-of-band
# (e.g. after Vertex AI Vector Search index is deployed).
# Each service SA is granted accessor rights only to its own secrets.

resource "google_secret_manager_secret" "vector_search_index_id" {
  secret_id = "rag-vector-search-index-id"
  project   = var.project_id
  labels    = var.labels

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret" "vector_search_index_endpoint_id" {
  secret_id = "rag-vector-search-index-endpoint-id"
  project   = var.project_id
  labels    = var.labels

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

# Both services need the Vector Search config
resource "google_secret_manager_secret_iam_member" "chunker_sa_index_id" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.vector_search_index_id.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.chunker_sa.member
}

resource "google_secret_manager_secret_iam_member" "chunker_sa_index_endpoint_id" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.vector_search_index_endpoint_id.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.chunker_sa.member
}

resource "google_secret_manager_secret_iam_member" "query_api_sa_index_id" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.vector_search_index_id.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.query_api_sa.member
}

resource "google_secret_manager_secret_iam_member" "query_api_sa_index_endpoint_id" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.vector_search_index_endpoint_id.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.query_api_sa.member
}

# ── Artifact Registry ─────────────────────────────────────────────────────────

resource "google_artifact_registry_repository" "rag_docker" {
  repository_id = "rag-docker"
  location      = var.region
  format        = "DOCKER"
  project       = var.project_id
  description   = "Docker images for RAG Cloud Run services"
  labels        = var.labels
}

# Cloud Build's default SA needs writer access to push built images.
# The default Cloud Build SA is: PROJECT_NUMBER@cloudbuild.gserviceaccount.com
resource "google_artifact_registry_repository_iam_member" "cloudbuild_sa_ar_writer" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.rag_docker.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${var.project_number}@cloudbuild.gserviceaccount.com"
}

# ── Billing Budget ────────────────────────────────────────────────────────────
# One budget at $20 with alert thresholds at 25% ($5), 50% ($10), 100% ($20).
# Notifications go to a dedicated Pub/Sub topic; a Cloud Monitoring notification
# channel delivers email. The topic can also trigger automated cost-control actions.

resource "google_pubsub_topic" "budget_alerts" {
  name    = "rag-budget-alerts"
  project = var.project_id
  labels  = var.labels
}

resource "google_monitoring_notification_channel" "budget_email" {
  display_name = "RAG Budget Alert Email"
  type         = "email"
  project      = var.project_id

  labels = {
    email_address = var.budget_alert_email
  }
}

resource "google_billing_budget" "rag_budget" {
  billing_account = var.billing_account_id
  display_name    = "enterprise-rag-gcp-${var.environment}"

  budget_filter {
    projects               = ["projects/${var.project_number}"]
    credit_types_treatment = "EXCLUDE_ALL_CREDITS"
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = "20"
    }
  }

  # $5 — early warning
  threshold_rules {
    threshold_percent = 0.25
    spend_basis       = "CURRENT_SPEND"
  }

  # $10 — halfway
  threshold_rules {
    threshold_percent = 0.5
    spend_basis       = "CURRENT_SPEND"
  }

  # $20 — at limit
  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "CURRENT_SPEND"
  }

  all_updates_rule {
    pubsub_topic                     = google_pubsub_topic.budget_alerts.id
    monitoring_notification_channels = [google_monitoring_notification_channel.budget_email.name]
  }
}
