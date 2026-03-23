#!/bin/bash
# scaffold.sh — run from the root of gcp-rag-enterprise
# Creates the full project directory structure with .gitkeep placeholders

set -e

echo "🏗️  Scaffolding enterprise-rag-gcp project structure..."

# ── Terraform ──────────────────────────────────────────
mkdir -p terraform/modules/networking
mkdir -p terraform/modules/storage
mkdir -p terraform/modules/vector-search
mkdir -p terraform/modules/cloud-run
mkdir -p terraform/modules/security
mkdir -p terraform/environments/dev
mkdir -p terraform/environments/prod

touch terraform/main.tf
touch terraform/variables.tf
touch terraform/outputs.tf
touch terraform/providers.tf
touch terraform/terraform.tfvars.example

touch terraform/modules/networking/.gitkeep
touch terraform/modules/storage/.gitkeep
touch terraform/modules/vector-search/.gitkeep
touch terraform/modules/cloud-run/.gitkeep
touch terraform/modules/security/.gitkeep
touch terraform/environments/dev/.gitkeep
touch terraform/environments/prod/.gitkeep

# ── Services: Chunker ──────────────────────────────────
mkdir -p services/chunker

touch services/chunker/main.py
touch services/chunker/requirements.txt
touch services/chunker/Dockerfile
touch services/chunker/.dockerignore

# ── Services: Query API ────────────────────────────────
mkdir -p services/query-api

touch services/query-api/main.py
touch services/query-api/requirements.txt
touch services/query-api/Dockerfile
touch services/query-api/.dockerignore

# ── Frontend ───────────────────────────────────────────
mkdir -p frontend/app
mkdir -p frontend/components
mkdir -p frontend/lib
mkdir -p frontend/public

touch frontend/app/.gitkeep
touch frontend/components/.gitkeep
touch frontend/lib/.gitkeep
touch frontend/public/.gitkeep

# ── Docs ───────────────────────────────────────────────
mkdir -p docs

touch docs/.gitkeep

# ── Root files ─────────────────────────────────────────
touch cloudbuild.yaml

echo ""
echo "✅  Done. Structure created:"
echo ""
find . -not -path './.git/*' -not -name '.DS_Store' | sort | sed 's|[^/]*/|  |g'
echo ""
echo "Next: git add . && git commit -m 'chore: add project scaffold' && git push"
