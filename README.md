# enterprise-rag-gcp

**Production-grade Retrieval-Augmented Generation on Google Cloud Platform — aligned to the GCP Well-Architected Framework. Deployable at demo scale for ~$77/month running, or ~$0.12/month with the cost control script between sessions.**

> Designed and built by [Chuck Tsocanos](https://chucktsocanos.com) — Technology Executive, AI Strategist, Cloud Transformation Leader.

---

## Overview

This repository contains the full implementation of an enterprise RAG (Retrieval-Augmented Generation) system on GCP. It serves two purposes:

- **Portfolio artifact** — demonstrating enterprise-grade cloud AI architecture for client conversations
- **GCP Professional Cloud Architect cert prep** — covering Vertex AI, Cloud Run, VPC peering, Service Networking, IAM, CMEK, Pub/Sub, Cloud Build, Firestore, and more

The system ingests technical books (EPUB, PDF, DOCX, PPTX), creates semantic embeddings using Google's `text-embedding-004`, stores them in Vertex AI Vector Search with chapter-aware metadata, and answers natural language questions by retrieving relevant context and generating streamed responses via Gemini 2.5 Flash — with book and chapter citations on every response.

---

## Architecture

### Three Independent Flows

The system separates infrastructure, application deployment, and data processing into completely independent flows:

**Infrastructure (Terraform, manual)** — Developer runs `terraform apply` locally. Manages 5 modules in dependency order: networking → storage → security → vector-search → cloud-run. No CI/CD involvement.

**Application (Cloud Build, automated)** — `git push` to main triggers Cloud Build. Builds all three Docker images in parallel on E2_MEDIUM (free tier), tags with `$COMMIT_SHA`, pushes to Artifact Registry, deploys to Cloud Run. ~5-8 minutes end to end.

**Data / AI pipeline (event-driven)** — Upload a document to GCS → `OBJECT_FINALIZE` → Pub/Sub push → OIDC-authenticated request to rag-chunker → extract chapters → chunk → embed → Firestore write → Vector Search upsert. Fully asynchronous.

### Stack

| Layer | Service | Purpose |
|---|---|---|
| Frontend | Cloud Run (Next.js) | Chat UI with SSE streaming, dark theme |
| Query API | Cloud Run (FastAPI) | RAG query pipeline, private VPC access |
| Ingestion | Cloud Run (LangChain) | Async chapter-aware chunking + embedding |
| Embeddings | Vertex AI text-embedding-004 | 768-dim dense vectors, RETRIEVAL_DOCUMENT task |
| Vector Store | Vertex AI Vector Search | DEDICATED_RESOURCES ANN, private VPC endpoint, ~14ms |
| Chunk Text | Firestore (rag-chunks) | Parallel chunk text retrieval after ANN lookup |
| LLM | Gemini 2.5 Flash | Streaming SSE generation with book/chapter citations |
| Messaging | Pub/Sub | Event-driven ingestion trigger via OIDC push |
| Storage | Cloud Storage (CMEK) | Raw document store, force_destroy=false |
| Secrets | Secret Manager | Vector Search IDs, runtime credentials |
| Networking | VPC + Service Networking | Private VPC peering to Vector Search, /16 range |
| CI/CD | Cloud Build + Artifact Registry | GitOps pipeline, immutable $COMMIT_SHA tags |
| IaC | Terraform | All GCP resources, 5 modules, prevent_destroy on index |

### Query Pipeline (10 steps)

| Step | Component | Latency |
|---|---|---|
| 1. User submits question | Browser → rag-frontend POST /query | — |
| 2. Frontend proxies | rag-frontend → rag-query-api SSE stream | — |
| 3. Embed question | text-embedding-004 (RETRIEVAL_QUERY task) | ~100ms |
| 4. Vector returns | 768-dim float array | — |
| 5. ANN lookup | Vector Search match() via private VPC gRPC | — |
| 6. Top-5 returned | SHA-256 chunk IDs + distances + metadata | ~14ms |
| 7. Fetch chunk text | Firestore parallel GET x5 (ThreadPoolExecutor) | ~10ms |
| 8. Build prompt | system + [Chunk N] (Book, Chapter) + question (~1,500 tokens) | <1ms |
| 9. Gemini streams | Token chunks → SSE event:token | ~2-4s |
| 10. Browser renders | event:token / event:metadata / event:done | continuous |

**Total end-to-end: ~6 seconds per query.**

---

## GCP Well-Architected Alignment

| Pillar | Implementation |
|---|---|
| **Security** | IAM least-privilege service accounts (chunker-sa, query-api-sa, cloudbuild-sa), CMEK on Cloud Storage (90-day key rotation), Secret Manager for all credentials, OIDC auth on Pub/Sub push, dedicated Cloud Build SA |
| **Reliability** | Cloud Run scale-to-zero with max-instances cap, Pub/Sub retry with exponential backoff, deterministic SHA-256 chunk IDs (idempotent re-ingestion), prevent_destroy on Vector Search index |
| **Performance Efficiency** | Vertex AI Vector Search DEDICATED_RESOURCES (~14ms ANN latency), Firestore parallel chunk retrieval (~10ms), Gemini Flash SSE streaming (first token ~2s), text-embedding-004 batched at 20 chunks/call |
| **Cost Optimization** | Scale-to-zero Cloud Run, Firestore free tier (50K reads/day), cost control script (7 modes, reduces from ~$77/mo to ~$0.12/mo between sessions), budget alerts at $5/$10/$20, E2_MEDIUM Cloud Build (120 free min/day) |
| **Operational Excellence** | Structured JSON logging (event, latency_ms, chunk_count, book_title), immutable $COMMIT_SHA image tags, 5-module Terraform with dependency outputs, cost control script with 7 teardown/restore modes |

---

## Cost Model

### Ingestion Cost (one-time per document)

| Item | Cost |
|---|---|
| text-embedding-004 (~500K chars per book) | ~$0.005/book |
| Cloud Storage, Pub/Sub, Cloud Run chunker | $0.00 (free tier) |
| Firestore writes (~600 chunks/book) | $0.00 (free tier) |
| **50-book corpus total** | **~$0.25** |

> Note: Re-ingesting the same documents re-charges embedding. Chunk IDs are deterministic so Vector Search and Firestore writes are idempotent, but the embedding API call fires regardless. A future optimization is to skip embedding for chunk IDs already present in the index.

### Monthly Operating Cost

| Mode | Monthly | Notes |
|---|---|---|
| **Running (endpoint live)** | **~$77/mo** | Vector Search DEDICATED (~$65) + VPC Connector (~$8) + NAT (~$4) |
| **Teardown** (index deployed, no endpoint) | ~$4/mo | NAT only |
| **Full teardown** (data only) | **~$0.12/mo** | GCS + Firestore + Artifact Registry at rest |

Queries themselves cost ~$0.0004 each (embedding + Gemini Flash at demo volume) — negligible.

### Cost Control Script

```bash
./rag-cost-control.sh                    # Check what is running and billing
./rag-cost-control.sh --teardown         # Stop VS endpoint + VPC connector (~$73/mo savings, 35-40 min to restore)
./rag-cost-control.sh --restore          # Bring back serving infrastructure
./rag-cost-control.sh --full-teardown    # Stop everything except data (~$79/mo savings, 55-60 min to restore)
./rag-cost-control.sh --full-restore     # Rebuild entire stack from scratch
./rag-cost-control.sh --stop-services    # Delete Cloud Run services (no endpoints accessible)
./rag-cost-control.sh --deep-teardown    # Destroy all infra, keep VS index + GCS bucket (~$0.12/mo)
./rag-cost-control.sh --bare-project     # Destroy ALL resources, leave empty GCP project (IRREVERSIBLE)
```

**What persists at each level:**

| Mode | GCS bucket | VS index | Firestore | AR images | Networking | Cloud Run |
|---|---|---|---|---|---|---|
| `--teardown` | Yes | Yes | Yes | Yes | Partial | Yes |
| `--full-teardown` | Yes | Yes | Yes | Yes | No | No |
| `--stop-services` | Yes | Yes | Yes | Yes | Yes | No |
| `--deep-teardown` | Yes | Yes | No | No | No | No |
| `--bare-project` | No | No | No | No | No | No |

---

## Repository Structure

```
enterprise-rag-gcp/
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── providers.tf                    # user_project_override=true for billing budget
│   ├── terraform.tfvars                # gitignored — project ID, billing account, image SHAs
│   └── modules/
│       ├── networking/                 # VPC, subnet, NAT, router, VPC connector, Service Networking peering
│       ├── storage/                    # GCS bucket (CMEK, force_destroy=false), KMS, Pub/Sub topic
│       ├── security/                   # 3 service accounts, IAM, Firestore DB, Secret Manager, billing budget
│       ├── vector-search/              # VS index (prevent_destroy=true), endpoint, deployed index (DEDICATED)
│       └── cloud-run/                  # rag-chunker, rag-query-api, Pub/Sub subscription, IAM bindings
├── services/
│   ├── chunker/                        # FastAPI + LangChain ingestion service
│   │   ├── main.py                     # Pub/Sub push handler, SUPPORTED_CONTENT_TYPES
│   │   ├── chunker.py                  # extract_epub(), embed_chunks(), Firestore writes
│   │   ├── requirements.txt
│   │   └── Dockerfile
│   └── query-api/                      # FastAPI query service with SSE streaming
│       ├── main.py                     # CORS middleware, /query SSE endpoint
│       ├── retriever.py                # match() via private gRPC, Firestore parallel fetch
│       ├── generator.py                # build_prompt(), Gemini streaming
│       ├── models.py                   # Pydantic schemas
│       ├── requirements.txt
│       └── Dockerfile
├── frontend/                           # Next.js 14, TypeScript, Tailwind, dark theme
│   ├── app/
│   ├── components/
│   ├── lib/
│   │   └── sse.ts                      # fetch + ReadableStream SSE client
│   └── package.json
├── cloudbuild.yaml                     # CI/CD — E2_MEDIUM, parallel builds, $COMMIT_SHA tags
├── rag-cost-control.sh                 # Cost management — teardown/restore/status (7 modes)
├── CLAUDE.md                           # Claude Code project instructions
├── .gitignore
├── LICENSE
└── README.md
```

---

## Prerequisites

- GCP project with billing enabled
- `gcloud` CLI authenticated (`gcloud auth application-default login`)
- Terraform >= 1.5
- Node.js >= 18 (frontend local dev only — Cloud Build handles container builds)
- Python >= 3.11 (service local dev only)
- Docker is **not required** — all container builds run remotely on Cloud Build

---

## Getting Started

### 1. Clone the repository

```bash
git clone https://github.com/chucklezt/gcp-rag-enterprise.git
cd gcp-rag-enterprise
```

### 2. Enable required APIs

```bash
gcloud config set project YOUR_PROJECT_ID

gcloud services enable \
  run.googleapis.com \
  aiplatform.googleapis.com \
  secretmanager.googleapis.com \
  cloudkms.googleapis.com \
  artifactregistry.googleapis.com \
  pubsub.googleapis.com \
  cloudbuild.googleapis.com \
  firestore.googleapis.com \
  servicenetworking.googleapis.com \
  billingbudgets.googleapis.com
```

### 3. Set Application Default Credentials quota project

```bash
gcloud auth application-default login
gcloud auth application-default set-quota-project YOUR_PROJECT_ID
```

> Alternatively, add `user_project_override = true` and `billing_project = var.project_id` to the Google provider in `terraform/providers.tf` — this is already done in this repo and eliminates the need to run the above command each session.

### 4. Configure terraform.tfvars

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
project_id         = "your-project-id"
region             = "us-central1"
environment        = "dev"
vpc_cidr           = "10.10.0.0/24"
vpc_connector_cidr = "10.10.1.0/28"
project_number     = "YOUR_PROJECT_NUMBER"   # gcloud projects describe YOUR_PROJECT_ID --format='value(projectNumber)'
billing_account_id = "XXXXXX-XXXXXX-XXXXXX"  # gcloud billing projects describe YOUR_PROJECT_ID --format='value(billingAccountName)' | sed 's/billingAccounts\///'
budget_alert_email = "you@example.com"
```

### 5. Provision infrastructure (5 modules)

```bash
terraform init
terraform plan
terraform apply
```

Modules provision in dependency order. The Vector Search index endpoint takes **20-40 minutes** — this is normal. Do not cancel.

After apply, store the Vector Search IDs in Secret Manager:

```bash
echo -n "YOUR_INDEX_ID" | gcloud secrets versions add rag-vector-search-index-id --data-file=-
echo -n "YOUR_ENDPOINT_ID" | gcloud secrets versions add rag-vector-search-index-endpoint-id --data-file=-
```

### 6. Build and push container images

Images are built automatically on every `git push` via Cloud Build. For the initial push before the trigger is configured, build manually:

```bash
# Build all three services
gcloud builds submit --config=cloudbuild.yaml
```

Update `terraform.tfvars` with the resulting image SHAs, then `terraform apply` again to deploy.

### 7. Configure Cloud Build trigger

In the GCP console: **Cloud Build → Triggers → Create Trigger**

- Source: GitHub (`chucklezt/gcp-rag-enterprise`), branch `^main$`
- Config: `cloudbuild.yaml`
- Service account: `cloudbuild-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com`
- Machine type: E2_MEDIUM (free tier — do **not** use E2_HIGHCPU_8)

### 8. Ingest documents

```bash
# Single document
gsutil cp your-document.epub gs://YOUR_PROJECT_ID-rag-documents/

# Bulk upload (parallel)
gsutil -m cp ./your-documents/*.epub gs://YOUR_PROJECT_ID-rag-documents/
```

Monitor ingestion progress:

```bash
gcloud logging read \
  "resource.type=cloud_run_revision AND resource.labels.service_name=rag-chunker" \
  --project=YOUR_PROJECT_ID \
  --limit=20 \
  --format=json \
  --freshness=5m \
  | python3 -c "
import json,sys
logs=json.load(sys.stdin)
for l in reversed(logs):
    p=l.get('jsonPayload',{})
    h=l.get('httpRequest',{})
    t=l.get('timestamp','')[:19]
    if h: print(t,'HTTP',h.get('status'))
    if p: print(t,json.dumps(p))
" 2>/dev/null
```

A successful ingestion looks like:
```
HTTP 200
{"event": "epub_extracted", "book_title": "...", "chapters": 101, "total_chunks": 613}
{"event": "document_processed", "chunk_count": 613, "embed_latency_ms": 14716, "total_latency_ms": 21669}
```

---

## Ingestion Pipeline Detail

The chunker handles EPUB, PDF, DOCX, and PPTX. EPUB ingestion is chapter-aware:

1. `ebooklib` iterates chapters in spine order
2. `BeautifulSoup` extracts clean text per chapter
3. `RecursiveCharacterTextSplitter` chunks each chapter independently (500 tokens, 50 overlap)
4. `text-embedding-004` embeds in batches of 20 chunks (~10K tokens/call, RETRIEVAL_DOCUMENT task)
5. Firestore batch write — `chunks/{SHA256_id}` with `text`, `book_title`, `chapter_title`, `chapter_index`
6. Vector Search `upsert_datapoints()` with metadata restricts

**Chunk IDs are deterministic** — `SHA-256({object_name}::ch{n}::chunk_{i})`. Re-uploading the same document is safe: Vector Search upserts overwrite identically and Firestore writes are idempotent. No duplicates, no cleanup required.

---

## Supported Document Formats

| Format | Handler | Metadata Restricts |
|---|---|---|
| EPUB | ebooklib + BeautifulSoup | book_title, chapter_title, chapter_index |
| PDF | pypdf | page_number |
| DOCX | python-docx | chapter_title (from heading style) |
| PPTX | python-pptx | slide_number |

---

## Development

### Running services locally

```bash
# Query API
cd services/query-api
pip install -r requirements.txt
uvicorn main:app --reload --port 8080

# Frontend
cd frontend
npm install
npm run dev   # hot reload — no restart needed for code changes
```

### Running with Claude Code

This project was built with [Claude Code](https://claude.ai/code). See [`CLAUDE.md`](CLAUDE.md) for project-specific instructions.

```bash
npm install -g @anthropic-ai/claude-code
claude
```

---

## Known Operational Notes

**Terraform state drift** — Every manual `gcloud` operation that creates or deletes a Terraform-managed resource causes state drift. Use `terraform import` after manual creates, `terraform state rm` after manual deletes.

**Vector Search deploy timing** — The index endpoint takes 20-40 minutes to deploy. GCP cleanup after undeploy takes 5-15 minutes. Always use the full resource path for `--index` in `gcloud ai index-endpoints deploy-index` — short numeric IDs return NOT_FOUND.

**Pub/Sub IAM chain** — Both `chunker-sa` and the Pub/Sub service agent (`service-PROJECT_NUMBER@gcp-sa-pubsub.iam.gserviceaccount.com`) need `roles/run.invoker` on rag-chunker. Pub/Sub mints the OIDC token as `chunker-sa`, so Cloud Run checks that email, not the service agent.

**Ingestion re-embedding cost** — Re-uploading a document re-charges the embedding API even though Vector Search and Firestore writes are idempotent. At ~$0.005/book this is negligible but worth knowing.

---

## Scaling to Production

The demo architecture scales to production with configuration changes only — no re-architecture required:

| Parameter | Demo | Production |
|---|---|---|
| Cloud Run min-instances | 0 | 2 |
| Cloud Run max-instances | 3 | 50 |
| Vector Search machine | e2-standard-2, 1 replica | n1-standard-16, 3 replicas |
| Vector Search shard size | SMALL | MEDIUM / LARGE |
| GCS bucket | Regional | Multi-region |
| Frontend access | allUsers (temp) | IAP + HTTPS Load Balancer |
| API access | allUsers (temp) | Apigee + IAP |
| Security perimeter | VPC peering only | VPC Service Controls + SCC Premium |
| CI/CD | Shared Cloud Build pool | Private Cloud Build pool + SLSA |

**Estimated production cost: ~$1,710/mo** (dominated by Apigee ~$600 and Vector Search HA ~$800). Security controls alone add ~$218/mo.

---

## Roadmap

- [ ] IAP (Identity-Aware Proxy) — replace allUsers before sharing URLs publicly
- [ ] Restrict CORS — change `allow_origins=["*"]` to frontend URL
- [ ] Skip re-embedding for existing chunk IDs (check Vector Search before calling embedding API)
- [ ] POC Terraform workspace — AUTOMATIC_RESOURCES, no VPC peering, ~$2/mo
- [ ] Multi-turn conversations — maintain query history across turns
- [ ] Apigee integration — enterprise API management
- [ ] VPC Service Controls — data exfiltration perimeter
- [ ] SLSA supply chain security — signed container provenance

---

## Security Notes

- No secrets in code — all credentials managed via Secret Manager
- No public IPs on backend services — query API and chunker are internal ingress only (allUsers binding is temporary dev exception, see Roadmap)
- CMEK encryption on Cloud Storage with 90-day key rotation
- Dedicated service accounts — one per Cloud Run service, least-privilege IAM only
- Private VPC peering to Vector Search — traffic never traverses the public internet
- VPC Service Controls — planned (see Roadmap)

---

## License

MIT — see [LICENSE](LICENSE) for details.

---

## Author

**Chuck Tsocanos**  
Technology Executive · AI Strategist · Cloud Transformation Leader

- Website: [chucktsocanos.com](https://chucktsocanos.com)
- LinkedIn: [linkedin.com/in/charlestsocanos](https://linkedin.com/in/charlestsocanos)

*Built with Claude and Claude Code.*
