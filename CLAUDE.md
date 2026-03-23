# CLAUDE.md — Project Instructions for Claude Code

This file is read automatically by Claude Code at the start of every session.
It contains project-specific context, conventions, and constraints.

---

## Project Overview

**enterprise-rag-gcp** is a production-grade Retrieval-Augmented Generation system
on Google Cloud Platform, aligned to the GCP Well-Architected Framework.

**Owner:** Chuck Tsocanos (https://chucktsocanos.com)
**Purpose:** Portfolio artifact + GCP Professional Cloud Architect cert prep

---

## GCP Configuration

```
Project ID:     [SET YOUR GCP PROJECT ID HERE]
Region:         us-central1
Zone:           us-central1-a
Bucket name:    [PROJECT_ID]-rag-documents
AR repo:        us-central1-docker.pkg.dev/[PROJECT_ID]/rag-docker
```

Always use `us-central1` unless there is a specific reason to deviate.
Always use the project ID from above — never hardcode a different project.

---

## Architecture Decisions (already made — do not re-litigate)

- **No public IPs on backend services** — Cloud Run query API is VPC-internal only
- **Dedicated service accounts** — one per Cloud Run service, never the default compute SA
- **CMEK on Cloud Storage** — via Cloud KMS, key ring in us-central1
- **Secret Manager** — all credentials stored there, never in env vars or code
- **VPC Service Controls** — perimeter wrapping Vertex AI and Cloud Storage
- **Vertex AI Vector Search** — not Pinecone, not ChromaDB, not FAISS in production
- **Gemini 2.5 Flash** — not Pro, not 1.5 — Flash is the cost/quality target
- **text-embedding-004** — 768 dimensions, 500-token chunks, 50-token overlap
- **Pub/Sub push subscription** — triggers Cloud Run chunker on GCS finalize event
- **Cloud Build** — CI/CD, not GitHub Actions — keeps everything GCP-native
- **Terraform** — all infrastructure as code, modular structure under terraform/modules/

---

## Naming Conventions

```
Service accounts:   [service]-sa          e.g. chunker-sa, query-api-sa
Cloud Run services: rag-[service]          e.g. rag-chunker, rag-query-api
GCS buckets:        [project-id]-rag-[purpose]
Pub/Sub topics:     rag-[event]            e.g. rag-ingest-trigger
Secret names:       [service]-[credential] e.g. query-api-vertex-key
KMS key rings:      rag-keyring
KMS keys:           rag-storage-key
AR repository:      rag-docker
Terraform modules:  snake_case
Python files:       snake_case
TS/JS files:        camelCase or kebab-case (Next.js convention)
```

---

## Code Style

### Python (Cloud Run services)
- Python 3.11+
- FastAPI for the query API
- LangChain for chunking and RAG orchestration
- Pydantic v2 for data models
- `structlog` for structured JSON logging
- Type hints on all functions
- Docstrings on all public functions and classes
- No print() — use logging only

### TypeScript / Next.js (frontend)
- Next.js 14 App Router
- TypeScript strict mode
- Tailwind CSS for styling — match chucktsocanos.com color palette:
  - Background: #0a0e1a
  - Panel: #111827
  - Blue accent: #2E5FA3 / #60a5fa
  - Text: #e2e8f0
  - Muted: #64748b
- No external UI component libraries — keep it lean
- SSE (Server-Sent Events) for streaming Gemini responses

### Terraform
- Terraform 1.5+
- Use modules for every logical group of resources
- All resources tagged: `project = "enterprise-rag-gcp"`, `owner = "chuck-tsocanos"`, `env = var.environment`
- Variables in variables.tf, outputs in outputs.tf
- No hardcoded values in resource blocks — always use variables or locals
- `terraform fmt` before every commit

---

## Security Rules (non-negotiable)

1. **Never commit secrets** — use Secret Manager references in all configs
2. **Never use the default compute service account** — always create dedicated SAs
3. **Never open firewall rules broader than necessary**
4. **Always set `ingress = internal-and-cloud-load-balancing`** on Cloud Run query API
5. **Always set `ingress = all`** only on the frontend-facing services if needed
6. **CMEK must be applied** to any new Cloud Storage bucket
7. **Container images must come from Artifact Registry** — never Docker Hub in production

---

## Terraform Module Structure

```
terraform/
├── main.tf               # Root module — calls all child modules
├── variables.tf          # Input variables
├── outputs.tf            # Output values
├── providers.tf          # Google provider config
├── terraform.tfvars.example  # Template — never commit actual .tfvars
└── modules/
    ├── networking/       # VPC, subnets, Cloud NAT, VPC connector, VPC SC
    ├── storage/          # GCS bucket + KMS key ring/key
    ├── vector-search/    # Vertex AI index + index endpoint
    ├── cloud-run/        # Both Cloud Run services + IAM bindings
    └── security/         # Service accounts, Secret Manager, Artifact Registry, Budget
```

---

## Service Architecture

### Ingestion flow
```
GCS upload → Pub/Sub (rag-ingest-trigger) → Cloud Run chunker
  → LangChain text splitter (500 tok / 50 overlap)
  → Vertex AI text-embedding-004 (768 dims)
  → Vertex AI Vector Search index upsert
```

### Query flow
```
Next.js UI → Cloud Run query-api (VPC internal)
  → text-embedding-004 (embed question)
  → Vector Search (top-5 ANN retrieval)
  → Gemini 2.5 Flash (streaming generation)
  → SSE stream → UI renders tokens live
```

---

## Observability Standards

Every Cloud Run request must emit a structured JSON log with these fields:
```json
{
  "severity": "INFO",
  "service": "rag-query-api",
  "trace_id": "...",
  "query_id": "...",
  "latency_ms": 342,
  "embed_latency_ms": 45,
  "retrieve_latency_ms": 87,
  "generate_latency_ms": 210,
  "chunk_count": 5,
  "input_tokens": 1487,
  "output_tokens": 312
}
```

Use OpenTelemetry SDK for tracing. Wrap each pipeline stage in a span:
`embed_query` → `retrieve_chunks` → `generate_response`

---

## Do Not

- Do not use `allUsers` or `allAuthenticatedUsers` in any IAM binding
- Do not create resources outside `us-central1` without explicit instruction
- Do not use `google_project_iam_member` with `roles/editor` or `roles/owner`
- Do not use `local-exec` or `remote-exec` provisioners in Terraform
- Do not store Terraform state locally — use GCS backend
- Do not use `latest` as a container image tag in production resources
- Do not add `--no-verify` to git commands
- Do not skip `terraform plan` before `terraform apply`

---

## Helpful Commands

```bash
# Authenticate gcloud
gcloud auth login
gcloud auth application-default login

# Set project
gcloud config set project YOUR_PROJECT_ID

# View Cloud Run logs
gcloud logging read "resource.type=cloud_run_revision" --limit=50 --format=json

# Tail logs live
gcloud beta run services logs tail rag-query-api --region=us-central1

# Terraform workflow
terraform init
terraform fmt -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan

# Build and push a container manually
gcloud builds submit --tag us-central1-docker.pkg.dev/PROJECT_ID/rag-docker/rag-chunker:latest services/chunker/
```
