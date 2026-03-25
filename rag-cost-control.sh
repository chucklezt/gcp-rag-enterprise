#!/usr/bin/env bash
# rag-cost-control.sh
# Checks billable RAG demo services and optionally tears them down.
# Usage: ./rag-cost-control.sh [--teardown] [--restore]

set -euo pipefail

PROJECT="rag-demo-491202"
REGION="us-central1"
TERRAFORM_DIR="$(dirname "$0")/terraform"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

check() { echo -e "${BLUE}==> $1${NC}"; }
ok()    { echo -e "${GREEN}    OK   $1${NC}"; }
warn()  { echo -e "${YELLOW}    COST $1${NC}"; }
err()   { echo -e "${RED}    ERR  $1${NC}"; }

echo ""
echo "RAG Demo Cost Control — project: $PROJECT"
echo "==========================================="
echo ""

# ── 1. Vector Search endpoint ──────────────────────────────────────────────
check "Vector Search endpoints"
ENDPOINTS=$(gcloud ai index-endpoints list \
  --region="$REGION" \
  --project="$PROJECT" \
  --format="value(name,displayName)" 2>/dev/null || echo "")

if [ -z "$ENDPOINTS" ]; then
  ok "No index endpoints found"
  VS_ENDPOINT_EXISTS=false
else
  while IFS=$'\t' read -r name display; do
    warn "Endpoint running: $display ($name) — ~\$65/mo"
  done <<< "$ENDPOINTS"
  VS_ENDPOINT_EXISTS=true
fi

# ── 2. Deployed indexes ─────────────────────────────────────────────────────
check "Deployed indexes"
ENDPOINT_ID=$(gcloud ai index-endpoints list \
  --region="$REGION" \
  --project="$PROJECT" \
  --format="value(name)" 2>/dev/null | head -1 || echo "")

if [ -n "$ENDPOINT_ID" ]; then
  DEPLOYED=$(gcloud ai index-endpoints describe "$ENDPOINT_ID" \
    --region="$REGION" \
    --project="$PROJECT" \
    --format="value(deployedIndexes[].id)" 2>/dev/null || echo "")
  if [ -n "$DEPLOYED" ]; then
    warn "Deployed index: $DEPLOYED — this is the primary cost driver"
  else
    ok "No deployed indexes on endpoint"
  fi
fi

# ── 3. VPC Connector ───────────────────────────────────────────────────────
check "VPC Access Connectors"
CONNECTORS=$(gcloud compute networks vpc-access connectors list \
  --region="$REGION" \
  --project="$PROJECT" \
  --format="value(name,state)" 2>/dev/null || echo "")

if [ -z "$CONNECTORS" ]; then
  ok "No VPC connectors found"
  CONNECTOR_EXISTS=false
else
  while IFS=$'\t' read -r name state; do
    warn "VPC connector: $name ($state) — ~\$8/mo"
  done <<< "$CONNECTORS"
  CONNECTOR_EXISTS=true
fi

# ── 4. Cloud Run services ──────────────────────────────────────────────────
check "Cloud Run services (scale-to-zero — low cost)"
gcloud run services list \
  --region="$REGION" \
  --project="$PROJECT" \
  --format="value(metadata.name,status.url)" 2>/dev/null | \
while IFS=$'\t' read -r name url; do
  ok "$name — scales to zero, minimal cost"
done

# ── 5. GCS bucket ──────────────────────────────────────────────────────────
check "GCS bucket"
BUCKET_SIZE=$(gsutil du -s "gs://${PROJECT}-rag-documents" 2>/dev/null | awk '{print $1}' || echo "0")
BUCKET_MB=$(echo "scale=1; $BUCKET_SIZE / 1048576" | bc 2>/dev/null || echo "?")
ok "rag-documents: ${BUCKET_MB}MB — within free tier (5GB)"

# ── 6. Summary ─────────────────────────────────────────────────────────────
echo ""
echo "Cost summary"
echo "============"
if [ "$VS_ENDPOINT_EXISTS" = true ]; then
  echo -e "${YELLOW}  Vector Search endpoint + deployed index:  ~\$65/mo${NC}"
else
  echo -e "${GREEN}  Vector Search endpoint:                   \$0 (not running)${NC}"
fi
if [ "${CONNECTOR_EXISTS:-false}" = true ]; then
  echo -e "${YELLOW}  VPC Connector:                            ~\$8/mo${NC}"
else
  echo -e "${GREEN}  VPC Connector:                            \$0 (not running)${NC}"
fi
echo -e "${GREEN}  Cloud Run (scale-to-zero):                ~\$0/mo${NC}"
echo -e "${GREEN}  GCS, Pub/Sub, KMS, Secret Manager:        ~\$2/mo${NC}"
echo ""

# ── Teardown mode ──────────────────────────────────────────────────────────
if [[ "${1:-}" == "--teardown" ]]; then
  echo -e "${RED}TEARDOWN MODE${NC}"
  echo "This will destroy the Vector Search endpoint and VPC connector."
  echo "Your vectors and EPUBs are safe — only serving infrastructure is removed."
  echo ""
  read -r -p "Proceed? (yes/no): " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 0
  fi

  echo ""
  check "Running terraform destroy for billable resources..."
  cd "$TERRAFORM_DIR"
  terraform destroy \
    -target=module.vector_search.google_vertex_ai_index_endpoint_deployed_index.rag_deployed_index \
    -target=module.vector_search.google_vertex_ai_index_endpoint.rag_endpoint \
    -target=module.networking.google_vpc_access_connector.rag_connector \
    -auto-approve

  echo ""
  echo -e "${GREEN}Teardown complete. Estimated savings: ~\$73/mo${NC}"
  echo "Run './rag-cost-control.sh --restore' to bring services back up."
fi

# ── Restore mode ───────────────────────────────────────────────────────────
if [[ "${1:-}" == "--restore" ]]; then
  echo -e "${BLUE}RESTORE MODE${NC}"
  echo "This will recreate the VPC connector, Vector Search endpoint,"
  echo "and redeploy the index. Index redeployment takes 20-40 minutes."
  echo ""
  read -r -p "Proceed? (yes/no): " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 0
  fi

  check "Recreating VPC connector and Vector Search endpoint..."
  cd "$TERRAFORM_DIR"
  terraform apply \
    -target=module.networking.google_vpc_access_connector.rag_connector \
    -target=module.vector_search.google_vertex_ai_index_endpoint.rag_endpoint \
    -auto-approve

  ENDPOINT_ID=$(terraform output -raw vector_search_endpoint_name 2>/dev/null || echo "")
  INDEX_ID=$(terraform output -raw vector_search_index_name 2>/dev/null || echo "")

  if [ -n "$ENDPOINT_ID" ] && [ -n "$INDEX_ID" ]; then
    check "Deploying index to endpoint (20-40 min)..."
    OP=$(gcloud ai index-endpoints deploy-index "$ENDPOINT_ID" \
      --deployed-index-id=rag_embeddings_deployed \
      --display-name="RAG Embeddings Deployed" \
      --index="$INDEX_ID" \
      --region="$REGION" \
      --project="$PROJECT" \
      --format="value(name)" 2>/dev/null || echo "")
    echo ""
    ok "Deploy operation submitted: $OP"
    echo "Check status with:"
    echo "  gcloud ai operations describe \$(basename $OP) \\"
    echo "    --index-endpoint=$ENDPOINT_ID \\"
    echo "    --region=$REGION --project=$PROJECT"
  fi

  echo ""
  echo -e "${GREEN}Restore initiated. Query API will be available once index deploy completes.${NC}"
fi

if [[ "${1:-}" != "--teardown" ]] && [[ "${1:-}" != "--restore" ]]; then
  echo "Usage:"
  echo "  ./rag-cost-control.sh              # check status only"
  echo "  ./rag-cost-control.sh --teardown   # shut down billable services"
  echo "  ./rag-cost-control.sh --restore    # bring services back up"
fi
