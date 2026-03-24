# ── KMS Key Ring ─────────────────────────────────────────────────────────────

resource "google_kms_key_ring" "rag_keyring" {
  name     = "rag-keyring"
  location = var.region
  project  = var.project_id
}

# ── KMS Crypto Key ───────────────────────────────────────────────────────────

resource "google_kms_crypto_key" "rag_storage_key" {
  name            = "rag-storage-key"
  key_ring        = google_kms_key_ring.rag_keyring.id
  rotation_period = var.kms_key_rotation_period
  purpose         = "ENCRYPT_DECRYPT"

  lifecycle {
    prevent_destroy = true
  }
}

# ── Grant GCS service agent permission to use the CMEK key ───────────────────
# GCS needs cryptoKeyEncrypterDecrypter to read/write objects with CMEK.
# The service agent identity is project-scoped and provisioned by GCP.

data "google_storage_project_service_account" "gcs_sa" {
  project = var.project_id
}

resource "google_kms_crypto_key_iam_member" "gcs_cmek" {
  crypto_key_id = google_kms_crypto_key.rag_storage_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${data.google_storage_project_service_account.gcs_sa.email_address}"
}

# ── GCS Bucket ───────────────────────────────────────────────────────────────

resource "google_storage_bucket" "rag_documents" {
  name                        = "${var.project_id}-rag-documents"
  location                    = var.region
  project                     = var.project_id
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  labels                      = var.labels

  encryption {
    default_kms_key_name = google_kms_crypto_key.rag_storage_key.id
  }

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 3
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  # Soft-delete window — 7 days
  soft_delete_policy {
    retention_duration_seconds = 604800
  }

  depends_on = [google_kms_crypto_key_iam_member.gcs_cmek]
}

# ── Pub/Sub Topic ─────────────────────────────────────────────────────────────

resource "google_pubsub_topic" "rag_ingest_trigger" {
  name    = "rag-ingest-trigger"
  project = var.project_id
  labels  = var.labels

  message_retention_duration = "86400s" # 24 hours
}

# ── Grant GCS service agent permission to publish to the topic ───────────────
# Required for GCS bucket notifications to deliver to Pub/Sub.

resource "google_pubsub_topic_iam_member" "gcs_pubsub_publisher" {
  project = var.project_id
  topic   = google_pubsub_topic.rag_ingest_trigger.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${data.google_storage_project_service_account.gcs_sa.email_address}"
}

# ── GCS Bucket Notification → Pub/Sub ────────────────────────────────────────
# Fires on OBJECT_FINALIZE (upload complete) — triggers the chunker pipeline.

resource "google_storage_notification" "ingest_notification" {
  bucket         = google_storage_bucket.rag_documents.name
  payload_format = "JSON_API_V1"
  topic          = google_pubsub_topic.rag_ingest_trigger.id
  event_types    = ["OBJECT_FINALIZE"]

  depends_on = [google_pubsub_topic_iam_member.gcs_pubsub_publisher]
}

# ── Pub/Sub Push Subscription → Cloud Run chunker ────────────────────────────
# Uses OIDC auth so Cloud Run can verify the caller is Pub/Sub.
# The chunker SA must have roles/run.invoker; that binding lives in the
# security/cloud-run modules to avoid circular dependencies.

resource "google_pubsub_subscription" "rag_ingest_push" {
  name    = "rag-ingest-push"
  topic   = google_pubsub_topic.rag_ingest_trigger.name
  project = var.project_id
  labels  = var.labels

  ack_deadline_seconds       = var.pubsub_ack_deadline_seconds
  message_retention_duration = "86400s"
  retain_acked_messages      = false

  push_config {
    push_endpoint = "${var.chunker_service_url}/ingest"

    oidc_token {
      service_account_email = var.chunker_service_account_email
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
