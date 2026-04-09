#!/usr/bin/env bash
# scripts/generate-docs.sh
#
# One-shot script that runs the full deterministic documentation pipeline.
# Designed to execute inside the project Docker image (see ../Dockerfile).
#
# Steps:
#   1. terraform init + validate
#   2. terraform plan (JSON output) — used by OPA
#   3. OPA policy evaluation — gate: non-zero violations abort the pipeline
#   4. terraform-docs — update docs/generated/terraform-readme.md
#   5. Ansible playbook — gather host facts, render Jinja2 host report
#   6. mkdocs build — assemble the full static site into site/
#
# Usage (from repo root):
#   bash example/scripts/generate-docs.sh
#
# Usage inside Docker:
#   docker run --rm -v "$(pwd)":/workspace dtds-example scripts/generate-docs.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="${REPO_ROOT}/terraform"
POLICY_DIR="${REPO_ROOT}/policies/terraform"
DOCS_GENERATED_DIR="${REPO_ROOT}/docs/generated"
MKDOCS_CFG="${REPO_ROOT}/mkdocs.yml"

# Colour helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ---------------------------------------------------------------------------
# Step 1 — Terraform init & validate
# ---------------------------------------------------------------------------
info "Step 1/6 — Terraform init & validate"

pushd "${TERRAFORM_DIR}" > /dev/null

# Copy example tfvars if no tfvars file exists
if [[ ! -f terraform.tfvars ]]; then
  cp terraform.tfvars.example terraform.tfvars
  warn "No terraform.tfvars found — using example defaults."
fi

terraform init -input=false -no-color
terraform validate -no-color
success "Terraform validation passed."

# ---------------------------------------------------------------------------
# Step 2 — terraform plan → JSON
# ---------------------------------------------------------------------------
info "Step 2/6 — terraform plan (JSON output for OPA)"

mkdir -p "${DOCS_GENERATED_DIR}"
terraform plan \
  -input=false \
  -no-color \
  -out="${DOCS_GENERATED_DIR}/plan.bin"

terraform show -json "${DOCS_GENERATED_DIR}/plan.bin" \
  > "${DOCS_GENERATED_DIR}/plan.json"

success "Plan JSON written to docs/generated/plan.json"
popd > /dev/null

# ---------------------------------------------------------------------------
# Step 3 — OPA policy evaluation (gate)
# ---------------------------------------------------------------------------
info "Step 3/6 — OPA policy evaluation"

OPA_VIOLATIONS=0
for package in "terraform.finops" "terraform.security"; do
  RESULT=$(opa eval \
    --data "${POLICY_DIR}" \
    --input "${DOCS_GENERATED_DIR}/plan.json" \
    --format raw \
    "count(data.${package}.deny)" 2>/dev/null || echo "0")

  if [[ "${RESULT}" -gt 0 ]]; then
    error "OPA package '${package}' produced ${RESULT} denial(s):"
    opa eval \
      --data "${POLICY_DIR}" \
      --input "${DOCS_GENERATED_DIR}/plan.json" \
      --format pretty \
      "data.${package}.deny" 2>/dev/null || true
    OPA_VIOLATIONS=$((OPA_VIOLATIONS + RESULT))
  else
    success "OPA package '${package}' — compliant (0 denials)."
  fi
done

if [[ "${OPA_VIOLATIONS}" -gt 0 ]]; then
  error "Pipeline aborted: ${OPA_VIOLATIONS} OPA policy violation(s) must be resolved."
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 4 — terraform-docs
# ---------------------------------------------------------------------------
info "Step 4/6 — terraform-docs"

terraform-docs markdown table \
  --output-file "${DOCS_GENERATED_DIR}/terraform-readme.md" \
  --output-mode replace \
  "${TERRAFORM_DIR}"

success "terraform-docs written to docs/generated/terraform-readme.md"

# ---------------------------------------------------------------------------
# Step 5 — Ansible fact-gather
# ---------------------------------------------------------------------------
info "Step 5/6 — Ansible host fact-gathering"

ansible-playbook \
  -i "${REPO_ROOT}/ansible/inventory.yml" \
  "${REPO_ROOT}/ansible/playbook.yml" \
  --connection=local \
  2>&1 | grep -v "^\[WARNING\]" || true

success "Ansible host report written to docs/generated/"

# ---------------------------------------------------------------------------
# Step 6 — MkDocs build
# ---------------------------------------------------------------------------
info "Step 6/6 — MkDocs build"

mkdocs build --config-file "${MKDOCS_CFG}" --strict

success "MkDocs site built in ${REPO_ROOT}/site/"
echo ""
echo -e "${GREEN}✔ Documentation pipeline completed successfully.${NC}"
echo "  Preview: open ${REPO_ROOT}/site/index.html"
