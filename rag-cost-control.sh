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
#   ./rag-cost-control.sh --stop-services  # delete all Cloud Run services (no endpoints accessible)
#   ./rag-cost-control.sh --deep-teardown  # destroy all infra, keep VS index + GCS bucket
#   ./rag-cost-control.sh --bare-project   # destroy ALL resources, leave only the empty GCP project

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

  # Uses direct gcloud commands instead of terraform destroy to avoid
  # dependency-chain issues where Terraform pulls in the VS index
  # (which has prevent_destroy = true) and aborts the entire plan.

  ENDPOINT_ID=$(gcloud ai index-endpoints list \
    --region="$REGION" --project="$PROJECT" \
    --format="value(name)" 2>/dev/null | head -1 || echo "")

  if [ -n "$ENDPOINT_ID" ]; then
    check "Undeploying index from endpoint..."
    gcloud ai index-endpoints undeploy-index "$ENDPOINT_ID" \
      --deployed-index-id=rag_embeddings_deployed \
      --region="$REGION" --project="$PROJECT" || true

    check "Deleting index endpoint..."
    gcloud ai index-endpoints delete "$ENDPOINT_ID" \
      --region="$REGION" --project="$PROJECT" --quiet || true
  else
    ok "No index endpoint found — skipping"
  fi

  check "Deleting VPC connector..."
  gcloud compute networks vpc-access connectors delete rag-connector-dev \
    --region="$REGION" --project="$PROJECT" --quiet || true

  check "Removing destroyed resources from Terraform state..."
  cd "$TERRAFORM_DIR"
  terraform state rm \
    module.vector_search.google_vertex_ai_index_endpoint_deployed_index.rag_deployed_index \
    2>/dev/null || true
  terraform state rm \
    module.vector_search.google_vertex_ai_index_endpoint.rag_endpoint \
    2>/dev/null || true
  terraform state rm \
    module.networking.google_vpc_access_connector.rag_connector \
    2>/dev/null || true

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

  # Uses direct gcloud commands for VS resources to avoid dependency-chain
  # issues where Terraform pulls in the VS index (prevent_destroy = true).
  # Cloud Run, NAT, and router are safe to destroy via Terraform since they
  # have no dependency on the VS index.

  ENDPOINT_ID=$(gcloud ai index-endpoints list \
    --region="$REGION" --project="$PROJECT" \
    --format="value(name)" 2>/dev/null | head -1 || echo "")

  if [ -n "$ENDPOINT_ID" ]; then
    check "Undeploying index from endpoint..."
    gcloud ai index-endpoints undeploy-index "$ENDPOINT_ID" \
      --deployed-index-id=rag_embeddings_deployed \
      --region="$REGION" --project="$PROJECT" || true

    check "Deleting index endpoint..."
    gcloud ai index-endpoints delete "$ENDPOINT_ID" \
      --region="$REGION" --project="$PROJECT" --quiet || true
  else
    ok "No index endpoint found — skipping"
  fi

  check "Deleting VPC connector..."
  gcloud compute networks vpc-access connectors delete rag-connector-dev \
    --region="$REGION" --project="$PROJECT" --quiet || true

  check "Removing VS resources from Terraform state..."
  cd "$TERRAFORM_DIR"
  terraform state rm \
    module.vector_search.google_vertex_ai_index_endpoint_deployed_index.rag_deployed_index \
    2>/dev/null || true
  terraform state rm \
    module.vector_search.google_vertex_ai_index_endpoint.rag_endpoint \
    2>/dev/null || true
  terraform state rm \
    module.networking.google_vpc_access_connector.rag_connector \
    2>/dev/null || true
  terraform state rm \
    module.vector_search.google_vertex_ai_index.rag_index \
    2>/dev/null || true

  check "Destroying Cloud Run, NAT, and router via Terraform..."
  terraform destroy \
    -target=module.cloud_run \
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
    DEPLOY_OUTPUT=$(gcloud ai index-endpoints deploy-index "$ENDPOINT_ID" \
      --deployed-index-id=rag_embeddings_deployed \
      --display-name="RAG Embeddings Deployed" \
      --index="$INDEX_ID" \
      --region="$REGION" --project="$PROJECT" 2>&1) || true
    echo "$DEPLOY_OUTPUT"
    OPERATION_ID=$(echo "$DEPLOY_OUTPUT" | grep -oP '(?<=operations/)\S+' || echo "")
    if [ -n "$OPERATION_ID" ]; then
      ok "Deploy operation started: $OPERATION_ID"
    fi
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
  INDEX_RESOURCE_ID="projects/$PROJECT/locations/$REGION/indexes/5187401301847179264"
  check "Re-importing Vector Search index into Terraform state..."
  if ! terraform state show module.vector_search.google_vertex_ai_index.rag_index &>/dev/null; then
    terraform import \
      module.vector_search.google_vertex_ai_index.rag_index \
      "$INDEX_RESOURCE_ID"
  else
    ok "Index already in Terraform state — skipping import"
  fi
  check "Step 1/3: Rebuilding networking and Cloud Run..."
  terraform apply \
    -target=module.networking \
    -target=module.cloud_run \
    -auto-approve
  check "Step 2/3: Recreating Vector Search endpoint..."
  if ! terraform apply \
    -target=module.vector_search.google_vertex_ai_index_endpoint.rag_endpoint \
    -auto-approve; then
    warn "Terraform apply failed — checking if endpoint was created in GCP anyway..."
    GCP_ENDPOINT_ID=$(gcloud ai index-endpoints list \
      --region="$REGION" --project="$PROJECT" \
      --format="value(name)" 2>/dev/null | head -1 || echo "")
    if [ -n "$GCP_ENDPOINT_ID" ]; then
      check "Endpoint exists in GCP but not in state — importing..."
      terraform import \
        module.vector_search.google_vertex_ai_index_endpoint.rag_endpoint \
        "$GCP_ENDPOINT_ID"
      ok "Endpoint imported successfully"
    else
      echo -e "${RED}Endpoint was not created in GCP. Re-run --full-restore to retry.${NC}"
      exit 1
    fi
  fi
  ENDPOINT_ID=$(terraform output -raw vector_search_endpoint_name 2>/dev/null || echo "")
  INDEX_ID=$(terraform output -raw vector_search_index_id 2>/dev/null || echo "")
  check "Step 3/3: Deploying index (20-40 min)..."
  if [ -n "$ENDPOINT_ID" ] && [ -n "$INDEX_ID" ]; then
    # INDEX_ID is the full resource path: projects/.../locations/.../indexes/...
    # The short numeric ID returns NOT_FOUND with gcloud deploy-index.
    DEPLOY_OUTPUT=$(gcloud ai index-endpoints deploy-index "$ENDPOINT_ID" \
      --deployed-index-id=rag_embeddings_deployed \
      --display-name="RAG Embeddings Deployed" \
      --index="$INDEX_ID" \
      --region="$REGION" --project="$PROJECT" 2>&1) || true
    echo "$DEPLOY_OUTPUT"
    OPERATION_ID=$(echo "$DEPLOY_OUTPUT" | grep -oP '(?<=operations/)\S+' || echo "")
    if [ -n "$OPERATION_ID" ]; then
      ok "Deploy operation started: $OPERATION_ID"
    fi
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

if [[ "${1:-}" == "--stop-services" ]]; then
  echo -e "${RED}STOP SERVICES MODE${NC}"
  echo "Deletes:  All Cloud Run services (chunker, query-api, frontend)"
  echo "Keeps:    All infrastructure (VS endpoint, VPC, networking, storage)"
  echo "Effect:   No endpoints accessible, no ingest processing"
  echo "Restore:  Redeploy via Cloud Build trigger or gcloud builds submit"
  echo ""
  read -r -p "Proceed? (yes/no): " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then echo "Aborted."; exit 0; fi

  SERVICES=$(gcloud run services list \
    --region="$REGION" --project="$PROJECT" \
    --format="value(metadata.name)" 2>/dev/null || echo "")

  if [ -z "$SERVICES" ]; then
    ok "No Cloud Run services found"
  else
    while read -r svc; do
      check "Deleting Cloud Run service: $svc..."
      gcloud run services delete "$svc" \
        --region="$REGION" --project="$PROJECT" --quiet || true
    done <<< "$SERVICES"
  fi

  check "Removing Cloud Run resources from Terraform state..."
  cd "$TERRAFORM_DIR"
  terraform state rm module.cloud_run 2>/dev/null || true

  echo ""
  echo -e "${GREEN}All services stopped. No endpoints are accessible.${NC}"
  echo "Redeploy via Cloud Build trigger or gcloud builds submit."
fi

if [[ "${1:-}" == "--deep-teardown" ]]; then
  echo -e "${RED}DEEP TEARDOWN MODE${NC}"
  echo "Destroys: All infrastructure — services, networking, IAM, secrets, Firestore, AR images"
  echo "Keeps:    Vector Search index (embeddings), GCS bucket (documents), KMS key (CMEK)"
  echo "Residual: ~\$0.12/mo (KMS + storage)"
  echo "Restore:  Full terraform apply + Cloud Build deploy"
  echo ""
  read -r -p "Proceed? (yes/no): " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then echo "Aborted."; exit 0; fi

  # --- 1. Cloud Run services (includes frontend which is not in Terraform) ---
  check "Deleting all Cloud Run services..."
  SERVICES=$(gcloud run services list \
    --region="$REGION" --project="$PROJECT" \
    --format="value(metadata.name)" 2>/dev/null || echo "")
  if [ -n "$SERVICES" ]; then
    while read -r svc; do
      echo "    Deleting $svc..."
      gcloud run services delete "$svc" \
        --region="$REGION" --project="$PROJECT" --quiet || true
    done <<< "$SERVICES"
  else
    ok "No Cloud Run services found"
  fi

  # --- 2. Vector Search endpoint (keep the index, destroy endpoint + deploy) ---
  ENDPOINT_ID=$(gcloud ai index-endpoints list \
    --region="$REGION" --project="$PROJECT" \
    --format="value(name)" 2>/dev/null | head -1 || echo "")
  if [ -n "$ENDPOINT_ID" ]; then
    check "Undeploying index from endpoint..."
    gcloud ai index-endpoints undeploy-index "$ENDPOINT_ID" \
      --deployed-index-id=rag_embeddings_deployed \
      --region="$REGION" --project="$PROJECT" || true
    check "Deleting index endpoint..."
    gcloud ai index-endpoints delete "$ENDPOINT_ID" \
      --region="$REGION" --project="$PROJECT" --quiet || true
  else
    ok "No index endpoint found"
  fi

  # --- 3. VPC connector ---
  check "Deleting VPC connector..."
  gcloud compute networks vpc-access connectors delete rag-connector-dev \
    --region="$REGION" --project="$PROJECT" --quiet 2>/dev/null || true

  # --- 4. Firestore database ---
  check "Deleting Firestore database (rag-chunks)..."
  gcloud firestore databases delete --database=rag-chunks \
    --project="$PROJECT" --quiet 2>/dev/null || true

  # --- 5. Artifact Registry images ---
  check "Deleting Artifact Registry images..."
  AR_IMAGES=$(gcloud artifacts docker images list \
    "us-central1-docker.pkg.dev/${PROJECT}/rag-docker" \
    --format="value(IMAGE)" --include-tags 2>/dev/null || echo "")
  if [ -n "$AR_IMAGES" ]; then
    while read -r img; do
      gcloud artifacts docker images delete "$img" \
        --delete-tags --quiet 2>/dev/null || true
    done <<< "$AR_IMAGES"
  fi

  # --- 6. Remove protected/preserved resources from Terraform state ---
  check "Cleaning Terraform state of protected and preserved resources..."
  cd "$TERRAFORM_DIR"
  for resource in \
    module.vector_search.google_vertex_ai_index_endpoint_deployed_index.rag_deployed_index \
    module.vector_search.google_vertex_ai_index_endpoint.rag_endpoint \
    module.vector_search.google_vertex_ai_index.rag_index \
    module.networking.google_vpc_access_connector.rag_connector \
    module.storage.google_kms_crypto_key.rag_storage_key \
    module.storage.google_kms_key_ring.rag_keyring \
    module.storage.google_kms_crypto_key_iam_member.gcs_cmek \
    module.storage.google_storage_bucket.rag_documents \
    module.storage.google_storage_notification.ingest_notification \
    module.storage.google_pubsub_topic_iam_member.gcs_pubsub_publisher; do
    terraform state rm "$resource" 2>/dev/null || true
  done

  # --- 7. Destroy everything remaining via Terraform ---
  check "Destroying all remaining infrastructure via Terraform..."
  terraform destroy -auto-approve || true

  echo ""
  echo -e "${GREEN}Deep teardown complete.${NC}"
  echo ""
  echo "Preserved:"
  echo "  - Vector Search index (all embeddings intact)"
  echo "  - GCS bucket gs://${PROJECT}-rag-documents (all documents intact)"
  echo "  - KMS key ring + key (required for bucket CMEK encryption)"
  echo ""
  echo "To rebuild: terraform apply + redeploy services via Cloud Build"
fi

if [[ "${1:-}" == "--bare-project" ]]; then
  echo -e "${RED}=========================================${NC}"
  echo -e "${RED}  BARE PROJECT MODE — IRREVERSIBLE${NC}"
  echo -e "${RED}=========================================${NC}"
  echo ""
  echo "Destroys: ALL resources — services, infrastructure, data, everything"
  echo "Keeps:    Only the empty GCP project and billing account"
  echo ""
  echo -e "${RED}All embeddings, documents, and Firestore data will be permanently lost.${NC}"
  echo ""
  read -r -p "Type 'DESTROY EVERYTHING' to confirm: " CONFIRM
  if [ "$CONFIRM" != "DESTROY EVERYTHING" ]; then echo "Aborted."; exit 0; fi

  # --- 1. Cloud Run services (includes frontend which is not in Terraform) ---
  check "Deleting all Cloud Run services..."
  SERVICES=$(gcloud run services list \
    --region="$REGION" --project="$PROJECT" \
    --format="value(metadata.name)" 2>/dev/null || echo "")
  if [ -n "$SERVICES" ]; then
    while read -r svc; do
      echo "    Deleting $svc..."
      gcloud run services delete "$svc" \
        --region="$REGION" --project="$PROJECT" --quiet || true
    done <<< "$SERVICES"
  else
    ok "No Cloud Run services found"
  fi

  # --- 2. Vector Search (prevent_destroy — must use gcloud) ---
  ENDPOINT_ID=$(gcloud ai index-endpoints list \
    --region="$REGION" --project="$PROJECT" \
    --format="value(name)" 2>/dev/null | head -1 || echo "")
  if [ -n "$ENDPOINT_ID" ]; then
    check "Undeploying index from endpoint..."
    gcloud ai index-endpoints undeploy-index "$ENDPOINT_ID" \
      --deployed-index-id=rag_embeddings_deployed \
      --region="$REGION" --project="$PROJECT" || true
    check "Deleting index endpoint..."
    gcloud ai index-endpoints delete "$ENDPOINT_ID" \
      --region="$REGION" --project="$PROJECT" --quiet || true
  else
    ok "No index endpoint found"
  fi

  check "Deleting Vector Search index (irreversible — all embeddings lost)..."
  INDEX_IDS=$(gcloud ai indexes list \
    --region="$REGION" --project="$PROJECT" \
    --format="value(name)" 2>/dev/null || echo "")
  if [ -n "$INDEX_IDS" ]; then
    while read -r idx; do
      echo "    Deleting $idx..."
      gcloud ai indexes delete "$idx" \
        --region="$REGION" --project="$PROJECT" --quiet || true
    done <<< "$INDEX_IDS"
  else
    ok "No indexes found"
  fi

  # --- 3. VPC connector (gcloud — already removed by --teardown pattern) ---
  check "Deleting VPC connector..."
  gcloud compute networks vpc-access connectors delete rag-connector-dev \
    --region="$REGION" --project="$PROJECT" --quiet 2>/dev/null || true

  # --- 4. GCS bucket contents ---
  check "Emptying GCS bucket (all versions)..."
  gsutil -m rm -ra "gs://${PROJECT}-rag-documents/**" 2>/dev/null || true

  # --- 5. KMS key versions (minimum 24-hour destruction delay) ---
  check "Scheduling KMS key versions for destruction..."
  KEY_VERSIONS=$(gcloud kms keys versions list \
    --key=rag-storage-key --keyring=rag-keyring \
    --location="$REGION" --project="$PROJECT" \
    --filter="state=ENABLED OR state=DISABLED" \
    --format="value(name)" 2>/dev/null || echo "")
  if [ -n "$KEY_VERSIONS" ]; then
    while read -r ver; do
      gcloud kms keys versions destroy "$ver" --project="$PROJECT" --quiet 2>/dev/null || true
    done <<< "$KEY_VERSIONS"
    warn "KMS key versions scheduled — destroyed after 24-hour wait"
  else
    ok "No active KMS key versions"
  fi

  # --- 6. Firestore database ---
  check "Deleting Firestore database (rag-chunks)..."
  gcloud firestore databases delete --database=rag-chunks \
    --project="$PROJECT" --quiet 2>/dev/null || true

  # --- 7. Artifact Registry images ---
  check "Deleting Artifact Registry images..."
  AR_IMAGES=$(gcloud artifacts docker images list \
    "us-central1-docker.pkg.dev/${PROJECT}/rag-docker" \
    --format="value(IMAGE)" --include-tags 2>/dev/null || echo "")
  if [ -n "$AR_IMAGES" ]; then
    while read -r img; do
      gcloud artifacts docker images delete "$img" \
        --delete-tags --quiet 2>/dev/null || true
    done <<< "$AR_IMAGES"
  fi

  # --- 8. Remove prevent_destroy resources from Terraform state ---
  check "Cleaning Terraform state of protected resources..."
  cd "$TERRAFORM_DIR"
  for resource in \
    module.vector_search.google_vertex_ai_index_endpoint_deployed_index.rag_deployed_index \
    module.vector_search.google_vertex_ai_index_endpoint.rag_endpoint \
    module.vector_search.google_vertex_ai_index.rag_index \
    module.networking.google_vpc_access_connector.rag_connector \
    module.storage.google_kms_crypto_key.rag_storage_key; do
    terraform state rm "$resource" 2>/dev/null || true
  done

  # --- 9. Destroy everything remaining via Terraform ---
  check "Destroying all remaining resources via Terraform..."
  terraform destroy -auto-approve || true

  # --- 10. Clean up Terraform state file ---
  check "Removing local Terraform state artifacts..."
  rm -f terraform.tfstate terraform.tfstate.backup .terraform.lock.hcl 2>/dev/null || true
  rm -rf .terraform 2>/dev/null || true

  echo ""
  echo -e "${GREEN}Bare project teardown complete.${NC}"
  echo ""
  echo "Notes:"
  echo "  - KMS key versions will be fully destroyed after 24 hours"
  echo "  - KMS key ring cannot be deleted (GCP limitation) but costs nothing"
  echo "  - The GCP project is otherwise empty"
fi

if [[ "${1:-}" != "--teardown" ]] && \
   [[ "${1:-}" != "--restore" ]] && \
   [[ "${1:-}" != "--full-teardown" ]] && \
   [[ "${1:-}" != "--full-restore" ]] && \
   [[ "${1:-}" != "--stop-services" ]] && \
   [[ "${1:-}" != "--deep-teardown" ]] && \
   [[ "${1:-}" != "--bare-project" ]]; then
  echo "Usage:"
  echo "  ./rag-cost-control.sh                  # status check"
  echo "  ./rag-cost-control.sh --teardown       # stop VS + VPC connector (~\$73/mo savings)"
  echo "  ./rag-cost-control.sh --restore        # bring back VS + VPC connector"
  echo "  ./rag-cost-control.sh --full-teardown  # stop everything except data (~\$79/mo savings)"
  echo "  ./rag-cost-control.sh --full-restore   # rebuild entire stack (~45-60 min)"
  echo "  ./rag-cost-control.sh --stop-services  # delete Cloud Run services (no endpoints)"
  echo "  ./rag-cost-control.sh --deep-teardown  # destroy all infra, keep index + bucket"
  echo "  ./rag-cost-control.sh --bare-project   # destroy ALL resources (irreversible)"
fi
