# enterprise-rag-gcp

**Production-grade Retrieval-Augmented Generation on Google Cloud Platform — aligned to the GCP Well-Architected Framework across all five pillars. Deployable at demo scale for ~$1.36/month.**

> Designed and built by [Chuck Tsocanos](https://chucktsocanos.com) — Technology Executive, AI Strategist, Cloud Transformation Leader.

---

## Overview

This repository contains the full implementation of an enterprise RAG (Retrieval-Augmented Generation) system on GCP. It is designed to serve dual purposes:

- **Portfolio artifact** — demonstrating enterprise-grade cloud AI architecture for VP-level and Fortune 100 client conversations
- **GCP Professional Cloud Architect cert prep** — covering Vertex AI, Cloud Run, VPC, IAM, CMEK, Pub/Sub, Cloud Build, and more

The system enables conversational question-answering over a document corpus (ebooks, technical docs, policy documents) using a fully GCP-native stack — with enterprise security controls, observability, and a CI/CD pipeline — at a cost that fits any POC budget.

---

## Architecture

![Enterprise RAG on GCP Architecture](docs/architecture-preview.png)

> Interactive architecture diagram: [`docs/gcp-rag-architecture.html`](docs/gcp-rag-architecture.html)
> Reference architecture document: [`docs/gcp-rag-reference-architecture.docx`](docs/gcp-rag-reference-architecture.docx)

### Stack

| Layer | Service | Purpose |
|---|---|---|
| Frontend | Next.js on Vercel | Chat UI with SSE streaming |
| Query API | Cloud Run (FastAPI) | RAG query pipeline, private VPC |
| Ingestion | Cloud Run (LangChain) | Async chunking + embedding |
| Embeddings | Vertex AI text-embedding-004 | 768-dim dense vectors |
| Vector Store | Vertex AI Vector Search | ANN retrieval, <100ms p99 |
| LLM | Gemini 2.5 Flash | Streaming generation |
| Messaging | Pub/Sub | Event-driven ingestion trigger |
| Storage | Cloud Storage (CMEK) | Raw document store |
| Secrets | Secret Manager | Credential management |
| Networking | VPC + VPC Service Controls | Private connectivity, no public IPs |
| Observability | Cloud Logging, Monitoring, Trace | Structured logs, dashboards, tracing |
| CI/CD | Cloud Build + Artifact Registry | GitOps deployment pipeline |
| IaC | Terraform | All GCP resources provisioned as code |

---

## GCP Well-Architected Alignment

| Pillar | Implementation |
|---|---|
| **Security** | IAM least-privilege service accounts, CMEK on Cloud Storage, VPC Service Controls, Secret Manager, no default SA usage |
| **Reliability** | Cloud Run scale-to-zero with max-instances cap, Pub/Sub retry with exponential backoff, health checks, multi-region GCS |
| **Performance Efficiency** | Vertex AI Vector Search (ANN, <100ms p99), Gemini Flash streaming SSE, async ingestion pipeline |
| **Cost Optimization** | Scale-to-zero compute, free tier maximization, budget alerts at $5/$10/$20, ~$1.36/month at demo scale |
| **Operational Excellence** | Structured JSON logging, OpenTelemetry tracing, Cloud Monitoring dashboard, Cloud Build GitOps pipeline |

---

## Cost Model

### One-Time Ingestion (5,000 pages)

| Item | Cost |
|---|---|
| text-embedding-004 (2.5M tokens) | $0.00–$0.25 |
| Cloud Storage | $0.00 (free tier) |
| Cloud Run chunker | $0.00 (free tier) |
| **Total** | **~$0.25** |

### Monthly Operating Cost (demo scale)

| Service | Monthly Cost |
|---|---|
| Cloud Run × 2 (scale-to-zero) | $0.00 |
| Vertex AI Vector Search | ~$0.10 |
| Gemini 2.5 Flash (1,000 queries) | ~$1.20 |
| Cloud Storage | $0.00 |
| Pub/Sub | $0.00 |
| Secret Manager | ~$0.06 |
| Logging / Monitoring / Trace | $0.00 |
| Artifact Registry | $0.00 |
| **Total** | **~$1.36/mo** |

Per-query cost: ~$0.0012 (0.12 cents) at 1,500 input + 300 output tokens via Gemini Flash.

---

## Repository Structure

```
enterprise-rag-gcp/
├── terraform/                  # All GCP infrastructure as code
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── modules/
│       ├── networking/         # VPC, subnets, NAT, VPC SC
│       ├── storage/            # GCS bucket, KMS/CMEK
│       ├── vector-search/      # Vertex AI index + endpoint
│       ├── cloud-run/          # Chunker + Query API services
│       └── security/           # IAM, Secret Manager, Artifact Registry
├── services/
│   ├── chunker/                # Python ingestion service (LangChain)
│   │   ├── main.py
│   │   ├── requirements.txt
│   │   └── Dockerfile
│   └── query-api/              # Python query service (FastAPI)
│       ├── main.py
│       ├── requirements.txt
│       └── Dockerfile
├── frontend/                   # Next.js chat UI
│   ├── app/
│   ├── components/
│   └── package.json
├── docs/                       # Architecture diagrams and reference docs
│   ├── gcp-rag-architecture.html
│   └── gcp-rag-reference-architecture.docx
├── cloudbuild.yaml             # CI/CD pipeline definition
├── CLAUDE.md                   # Claude Code project instructions
├── .gitignore
├── LICENSE
└── README.md
```

---

## Prerequisites

- GCP project with billing enabled
- `gcloud` CLI authenticated (`gcloud auth login`)
- Terraform >= 1.5
- Node.js >= 18 (for Next.js frontend)
- Python >= 3.11 (for Cloud Run services)
- Docker (for local container builds)

---

## Getting Started

### 1. Clone the repository

```bash
git clone https://github.com/YOUR_USERNAME/enterprise-rag-gcp.git
cd enterprise-rag-gcp
```

### 2. Configure your GCP project

```bash
gcloud config set project YOUR_PROJECT_ID

gcloud services enable \
  run.googleapis.com \
  aiplatform.googleapis.com \
  secretmanager.googleapis.com \
  cloudkms.googleapis.com \
  artifactregistry.googleapis.com \
  pubsub.googleapis.com \
  cloudbuild.googleapis.com
```

### 3. Provision infrastructure

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project ID and settings

terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### 4. Ingest documents

```bash
# Upload documents to the GCS bucket
gsutil -m cp ./your-documents/*.pdf gs://YOUR_BUCKET_NAME/

# Pub/Sub automatically triggers the ingestion pipeline
# Monitor progress in Cloud Logging
```

### 5. Deploy the frontend

```bash
cd frontend
npm install
vercel deploy
```

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
npm run dev
```

### Running with Claude Code

This project is designed to be built and iterated with [Claude Code](https://claude.ai/code). See [`CLAUDE.md`](CLAUDE.md) for project-specific instructions that Claude Code reads automatically.

```bash
# Install Claude Code
npm install -g @anthropic-ai/claude-code

# Start a session in the repo root
claude
```

---

## Deployment Pipeline

Every push to `main` triggers the Cloud Build pipeline defined in `cloudbuild.yaml`:

```
git push → Cloud Build trigger
  → Build container images
  → Push to Artifact Registry
  → Vulnerability scan
  → Deploy to Cloud Run
  → Terraform plan (on PR)
```

---

## Security Notes

- **No secrets in code** — all credentials managed via Secret Manager
- **No public IPs on backend** — Cloud Run query API is VPC-internal only
- **CMEK encryption** — Cloud Storage bucket encrypted with customer-managed KMS key
- **Dedicated service accounts** — one per Cloud Run service, least-privilege IAM
- **VPC Service Controls** — perimeter around Vertex AI and Cloud Storage
- See [Security Pillar documentation](docs/gcp-rag-reference-architecture.docx) for full detail

---

## Scaling to Production

The demo architecture scales to production with configuration changes only — no re-architecture required:

| Parameter | Demo | Production |
|---|---|---|
| Cloud Run min-instances | 0 | 2 |
| Cloud Run max-instances | 3 | 50 |
| Vector Search shard size | SMALL | MEDIUM / LARGE |
| GCS bucket | Regional | Multi-region |
| Gemini model | Flash | Flash or Pro depending on quality needs |

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

## Author

**Chuck Tsocanos**
Technology Executive · AI Strategist · Cloud Transformation Leader

- Website: [chucktsocanos.com](https://chucktsocanos.com)
- LinkedIn: [linkedin.com/in/chucktsocanos](https://linkedin.com/in/chucktsocanos)

*Design prompted by Chuck Tsocanos using Claude.*
# Enterprise RAG on GCP
