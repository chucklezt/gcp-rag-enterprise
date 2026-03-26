#!/usr/bin/env bash
# rag-cost-control.sh
# Checks billable RAG demo services and optionally tears them down.
#
# Usage:
#   ./rag-cost-control.sh                  # status check only
#   ./rag-cost-control.sh --teardown       # stop VS endpoint + VPC connector (~$73/mo savings)
#   ./rag-cost-control.sh --restore        # bring back VS endpoint + VPC connector
#   ./rag-cost-control.sh --full-teardown  # stop everything except GCS bucket + VS index (~$79/mo savings)
#   ./rag-cost-control.sh --full-restore   # rebuild entire stack from scratch (~45-60 min)

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

echo ""
echo "RAG Demo Cost Control — project: $PROJECT"
echo "==========================================="
echo ""

check "Vector Search endpoints"
ENDPOINTS=$(gcloud ai index-endpoints list \
  --region="$REGION" --project="$PROJECT" \
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

check "Deployed indexes"
ENDPOINT_ID=$(gcloud ai index-endpoints list \
  --region="$REGION" --project="$PROJECT" \
  --format="value(name)" 2>/dev/null | head -1 || echo "")
if [ -n "$ENDPOINT_ID" ]; then
  DEPLOYED=$(gcloud ai index-endpoints describe "$ENDPOINT_ID" \
    --region="$REGION" --project="$PROJECT" \
    --format="value(deployedIndexes[].id)" 2>/dev/null || echo "")
  if [ -n "$DEPLOYED" ]; then
    warn "Deployed index: $DEPLOYED — primary cost driver"
  else
    ok "No deployed indexes on endpoint"
  fi
fi

check "VPC Access Connectors"
CONNECTORS=$(gcloud compute networks vpc-access connectors list \
  --region="$REGION" --project="$PROJECT" \
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

check "Cloud NAT"
NAT=$(gcloud compute routers nats list \
  --router=rag-router-dev --region="$REGION" --project="$PROJECT" \
  --format="value(name)" 2>/dev/null || echo "")
if [ -z "$NAT" ]; then
  ok "Cloud NAT not running"
  NAT_EXISTS=false
else
  warn "Cloud NAT running: $NAT — ~\$4/mo uptime + usage"
  NAT_EXISTS=true
fi

check "Cloud Run services (scale-to-zero)"
gcloud run services list \
  --region="$REGION" --project="$PROJECT" \
  --format="value(metadata.name)" 2>/dev/null | \
while read -r name; do
  ok "$name — scales to zero, ~\$0/mo"
done

check "GCS bucket"
BUCKET_SIZE=$(gsutil du -s "gs://${PROJECT}-rag-documents" 2>/dev/null | awk '{print $1}' || echo "0")
BUCKET_MB=$(echo "scale=1; $BUCKET_SIZE / 1048576" | bc 2>/dev/null || echo "?")
ok "rag-documents: ${BUCKET_MB}MB — within 5GB free tier"

echo ""
echo "Cost summary"
echo "============"
TOTAL=0
if [ "$VS_ENDPOINT_EXISTS" = true ]; then
  echo -e "${YELLOW}  Vector Search endpoint + deployed index:  ~\$65/mo${NC}"
  TOTAL=$((TOTAL + 65))
else
  echo -e "${GREEN}  Vector Search endpoint:                   \$0${NC}"
fi
if [ "${CONNECTOR_EXISTS:-false}" = true ]; then
  echo -e "${YELLOW}  VPC Connector:                            ~\$8/mo${NC}"
  TOTAL=$((TOTAL + 8))
else
  echo -e "${GREEN}  VPC Connector:                            \$0${NC}"
fi
if [ "${NAT_EXISTS:-false}" = true ]; then
  echo -e "${YELLOW}  Cloud NAT:                                ~\$4/mo${NC}"
  TOTAL=$((TOTAL + 4))
else
  echo -e "${GREEN}  Cloud NAT:                                \$0${NC}"
fi
echo -e "${GREEN}  Cloud Run (scale-to-zero):                ~\$0/mo${NC}"
echo -e "${GREEN}  GCS, Pub/Sub, KMS, Secret Manager:        ~\$0.12/mo${NC}"
echo ""
echo -e "  Estimated current spend: ~\$${TOTAL}/mo"
echo ""

if [[ "${1:-}" == "--teardown" ]]; then
  echo -e "${RED}TEARDOWN MODE${NC}"
  echo "Destroys: Vector Search endpoint + deployed index + VPC connector"
  echo "Keeps:    Cloud NAT, Cloud Router, VPC, GCS bucket, VS index"
  echo "Savings:  ~\$73/mo"
  echo ""
  read -r -p "Proceed? (yes/no): " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then echo "Aborted."; exit 0; fi
  cd "$TERRAFORM_DIR"
  # WARNING: Never target module.vector_search.google_vertex_ai_index.rag_index here.
  # The index contains all vector embeddings and takes hours to rebuild from scratch.
  # Only destroy the deployed index and endpoint — the index itself must be preserved.
  terraform destroy \
    -target=module.vector_search.google_vertex_ai_index_endpoint_deployed_index.rag_deployed_index \
    -target=module.vector_search.google_vertex_ai_index_endpoint.rag_endpoint \
    -target=module.networking.google_vpc_access_connector.rag_connector \
    -auto-approve
  echo ""
  echo -e "${GREEN}Teardown complete. Savings: ~\$73/mo${NC}"
  echo "Run './rag-cost-control.sh --restore' to bring services back up."
fi

if [[ "${1:-}" == "--full-teardown" ]]; then
  echo -e "${RED}FULL TEARDOWN MODE${NC}"
  echo "Destroys: Everything except GCS bucket contents and Vector Search index"
  echo "Keeps:    EPUBs in GCS, vectors in VS index, Artifact Registry images"
  echo "Savings:  ~\$79/mo"
  echo "Residual: ~\$0.12/mo (KMS + Secret Manager)"
  echo "Restore:  ~45-60 min with --full-restore"
  echo ""
  read -r -p "Proceed? (yes/no): " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then echo "Aborted."; exit 0; fi
  cd "$TERRAFORM_DIR"
  # WARNING: Never target module.vector_search.google_vertex_ai_index.rag_index here.
  # The index contains all vector embeddings and takes hours to rebuild from scratch.
  # Only destroy the deployed index and endpoint — the index itself must be preserved.
  terraform destroy \
    -target=module.vector_search.google_vertex_ai_index_endpoint_deployed_index.rag_deployed_index \
    -target=module.vector_search.google_vertex_ai_index_endpoint.rag_endpoint \
    -target=module.cloud_run \
    -target=module.networking.google_vpc_access_connector.rag_connector \
    -target=module.networking.google_compute_router_nat.rag_nat \
    -target=module.networking.google_compute_router.rag_router \
    -auto-approve
  echo ""
  echo -e "${GREEN}Full teardown complete. Savings: ~\$79/mo${NC}"
  echo "Run './rag-cost-control.sh --full-restore' to rebuild everything."
fi

if [[ "${1:-}" == "--restore" ]]; then
  echo -e "${BLUE}RESTORE MODE${NC}"
  echo "Recreates: VPC connector + Vector Search endpoint + deploys index"
  echo "Time:      ~30-40 min"
  echo ""
  read -r -p "Proceed? (yes/no): " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then echo "Aborted."; exit 0; fi
  cd "$TERRAFORM_DIR"
  terraform apply \
    -target=module.networking.google_vpc_access_connector.rag_connector \
    -target=module.vector_search.google_vertex_ai_index_endpoint.rag_endpoint \
    -auto-approve
  ENDPOINT_ID=$(terraform output -raw vector_search_endpoint_name 2>/dev/null || echo "")
  INDEX_ID=$(terraform output -raw vector_search_index_id 2>/dev/null || echo "")
  if [ -n "$ENDPOINT_ID" ] && [ -n "$INDEX_ID" ]; then
    check "Deploying index to endpoint (20-40 min)..."
    # INDEX_ID is the full resource path: projects/.../locations/.../indexes/...
    # The short numeric ID returns NOT_FOUND with gcloud deploy-index.
    gcloud ai index-endpoints deploy-index "$ENDPOINT_ID" \
      --deployed-index-id=rag_embeddings_deployed \
      --display-name="RAG Embeddings Deployed" \
      --index="$INDEX_ID" \
      --region="$REGION" --project="$PROJECT" 2>/dev/null || true
    check "Updating Secret Manager with new endpoint ID..."
    echo -n "$ENDPOINT_ID" | gcloud secrets versions add rag-vector-search-index-endpoint-id \
      --data-file=- --project="$PROJECT"
    ok "Secret updated: $ENDPOINT_ID"
    echo ""
    ok "Check deploy status:"
    echo "  gcloud ai index-endpoints describe $ENDPOINT_ID \\"
    echo "    --region=$REGION --project=$PROJECT --format='yaml(deployedIndexes)'"
  fi
  echo ""
  echo -e "${GREEN}Restore initiated. Ready once index deploys.${NC}"
fi

if [[ "${1:-}" == "--full-restore" ]]; then
  echo -e "${BLUE}FULL RESTORE MODE${NC}"
  echo "Rebuilds: Entire stack from scratch"
  echo "Time:     ~45-60 min total"
  echo ""
  read -r -p "Proceed? (yes/no): " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then echo "Aborted."; exit 0; fi
  cd "$TERRAFORM_DIR"
  check "Step 1/3: Rebuilding networking and Cloud Run..."
  terraform apply \
    -target=module.networking \
    -target=module.cloud_run \
    -auto-approve
  check "Step 2/3: Recreating Vector Search endpoint..."
  terraform apply \
    -target=module.vector_search.google_vertex_ai_index_endpoint.rag_endpoint \
    -auto-approve
  ENDPOINT_ID=$(terraform output -raw vector_search_endpoint_name 2>/dev/null || echo "")
  INDEX_ID=$(terraform output -raw vector_search_index_id 2>/dev/null || echo "")
  check "Step 3/3: Deploying index (20-40 min)..."
  if [ -n "$ENDPOINT_ID" ] && [ -n "$INDEX_ID" ]; then
    # INDEX_ID is the full resource path: projects/.../locations/.../indexes/...
    # The short numeric ID returns NOT_FOUND with gcloud deploy-index.
    gcloud ai index-endpoints deploy-index "$ENDPOINT_ID" \
      --deployed-index-id=rag_embeddings_deployed \
      --display-name="RAG Embeddings Deployed" \
      --index="$INDEX_ID" \
      --region="$REGION" --project="$PROJECT" 2>/dev/null || true
    check "Updating Secret Manager with new endpoint ID..."
    echo -n "$ENDPOINT_ID" | gcloud secrets versions add rag-vector-search-index-endpoint-id \
      --data-file=- --project="$PROJECT"
    ok "Secret updated: $ENDPOINT_ID"
    echo ""
    ok "Check deploy status:"
    echo "  gcloud ai index-endpoints describe $ENDPOINT_ID \\"
    echo "    --region=$REGION --project=$PROJECT --format='yaml(deployedIndexes)'"
  fi
  echo ""
  echo -e "${GREEN}Full restore complete. Ready once index deploys (~20-40 min).${NC}"
fi

if [[ "${1:-}" != "--teardown" ]] && \
   [[ "${1:-}" != "--restore" ]] && \
   [[ "${1:-}" != "--full-teardown" ]] && \
   [[ "${1:-}" != "--full-restore" ]]; then
  echo "Usage:"
  echo "  ./rag-cost-control.sh                  # status check"
  echo "  ./rag-cost-control.sh --teardown       # stop VS + VPC connector (~\$73/mo savings)"
  echo "  ./rag-cost-control.sh --restore        # bring back VS + VPC connector"
  echo "  ./rag-cost-control.sh --full-teardown  # stop everything except data (~\$79/mo savings)"
  echo "  ./rag-cost-control.sh --full-restore   # rebuild entire stack (~45-60 min)"
fi
