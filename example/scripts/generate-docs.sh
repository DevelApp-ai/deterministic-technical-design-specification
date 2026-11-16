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
#   5. SpecTree AST generation — spectree-parse.py → docs/generated/spectree/
#      + shared traceability metadata normalization (ADR-0019) →
#        docs/generated/traceability/metadata-v1.json
#      + TDS composition manifests (ADR-0021) — generate-tds-composition.py →
#        docs/generated/tds/*.composition.json (sources bound to git blob SHAs)
#   6. .NET build + DocFX + OpenAPI + C4 diagrams — API reference markdown,
#      OpenAPI reference page, and C4 architecture diagrams
#   7. DSC resource documentation — pwsh dsc/build.ps1 → docs/generated/dsc-resources/
#   8. Ansible playbook — gather host facts, render Jinja2 host report
#   9. mkdocs build — assemble the full static site into site/
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
DSC_DIR="${REPO_ROOT}/dsc"
MKDOCS_CFG="${REPO_ROOT}/mkdocs.yml"
DOTNET_API_DIR="${REPO_ROOT}/docs/generated/dotnet-api"

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
info "Step 1/8 — Terraform init & validate"

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
info "Step 2/8 — terraform plan (JSON output for OPA)"

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
info "Step 3/8 — OPA policy evaluation"

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
info "Step 4/8 — terraform-docs"

terraform-docs markdown table \
  --output-file "${DOCS_GENERATED_DIR}/terraform-readme.md" \
  --output-mode replace \
  "${TERRAFORM_DIR}"

success "terraform-docs written to docs/generated/terraform-readme.md"

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Step 5 — SpecTree AST generation
# ---------------------------------------------------------------------------
info "Step 5/9 — SpecTree AST generation"

if command -v python3 &> /dev/null; then
  # Parse every specification under spectree/specs/ into versioned JSON
  # ASTs, validated against spectree/schemas/spectree-ast-v1.schema.json.
  # The selftest runs first: parser regressions abort the pipeline before
  # any artefacts are written (see ADR-0018).
  python3 "${REPO_ROOT}/scripts/spectree-parse.py" --selftest
  python3 "${REPO_ROOT}/scripts/spectree-parse.py" --all
  success "SpecTree ASTs written to docs/generated/spectree/"

  # Normalize every spec source family (MoSCoW tables, ADR front-matter,
  # Rego metadocs, SpecTree ASTs) onto the shared metadata contract of
  # ADR-0019, validated against
  # spectree/schemas/traceability-metadata-v1.schema.json.
  python3 "${REPO_ROOT}/scripts/normalize-traceability-metadata.py" --selftest
  python3 "${REPO_ROOT}/scripts/normalize-traceability-metadata.py" --all
  success "Normalized metadata written to docs/generated/traceability/metadata-v1.json"

  # SpecTree validation gate (ADR-0020): ERROR findings abort the pipeline;
  # WARNING findings are printed for visibility.
  if command -v opa &> /dev/null; then
    OPA="$(command -v opa)" bash "${REPO_ROOT}/scripts/spectree-gate.sh"
    success "SpecTree validation gate passed (0 error findings)"
  else
    warn "opa not found — skipping the SpecTree validation gate."
    warn "Install OPA to enable this step."
  fi

  # TDS composition manifests (ADR-0021): parse spectree/tds/*.tds and
  # emit the drift-gated composition report binding every composed
  # source to its git blob SHA.
  python3 "${REPO_ROOT}/scripts/generate-tds-composition.py" --selftest
  python3 "${REPO_ROOT}/scripts/generate-tds-composition.py" --all
  success "TDS composition report written to docs/generated/tds/"
else
  warn "python3 not found — skipping SpecTree AST generation."
  warn "Install Python 3 to enable this step."
  # Ensure the output directory exists so MkDocs can still build
  mkdir -p "${DOCS_GENERATED_DIR}/spectree"
fi


# Step 6 — .NET build gate + DocFX API reference + OpenAPI rendering
# ---------------------------------------------------------------------------
info "Step 6/9 — .NET build gate + DocFX + OpenAPI + C4 diagrams"

DOTNET_DIR="${REPO_ROOT}/dotnet"

if command -v dotnet &> /dev/null; then
  pushd "${DOTNET_DIR}" > /dev/null

  # Remove the stale OpenAPI document so the build-time GetDocument target
  # always re-emits it (MSBuild skips up-to-date targets otherwise).
  rm -f "${DOCS_GENERATED_DIR}/openapi.json"

  # Build first: the deterministic .NET build gate (warnings-as-errors +
  # Roslyn analyzers) must pass before any documentation is generated from
  # the compiled assemblies. The build also emits the native OpenAPI
  # document (Microsoft.AspNetCore.OpenApi build-time generation) to
  # docs/generated/openapi.json. The NetArchTest architecture policies run
  # as a separate test job in CI before the docs-build stage.
  dotnet build MyApp.slnx -c Release
  success ".NET solution built (Release, zero warnings required)."
  success "OpenAPI document emitted to docs/generated/openapi.json"

  if command -v python3 &> /dev/null; then
    python3 "${REPO_ROOT}/scripts/generate-openapi-docs.py"
    success "OpenAPI reference rendered to docs/application/api-reference.md"
  else
    warn "python3 not found — skipping OpenAPI reference rendering."
  fi

  # Restore the pinned local tools from the tool manifest
  # (dotnet/dotnet-tools.json, currently docfx 2.81.0) before invoking them:
  # a local tool manifest takes precedence over any globally installed docfx,
  # so the manifest is the single source of truth for the pinned version.
  dotnet tool restore
  success "Local .NET tools restored from dotnet/dotnet-tools.json"

  # docfx metadata with outputFormat "markdown" renders the API reference
  # straight to MkDocs-consumable markdown.
  dotnet docfx metadata docs/docfx.json
  success "DocFX API reference written to docs/generated/dotnet-api/"

  # C4 architecture diagrams (C4Sharp, pinned in
  # tools/MyApp.Architecture.Diagrams). The generator writes Mermaid
  # sources (+ PlantUML) to docs/generated/architecture/; the assembler
  # embeds them into the MkDocs page
  # docs/application/architecture-diagrams.md.
  dotnet run --project tools/MyApp.Architecture.Diagrams -c Release --no-build
  success "C4 diagram sources written to docs/generated/architecture/"

  if command -v python3 &> /dev/null; then
    python3 "${REPO_ROOT}/scripts/generate-c4-diagram-docs.py"
    success "C4 diagrams embedded in docs/application/architecture-diagrams.md"
  else
    warn "python3 not found — skipping C4 diagram page assembly."
  fi

  popd > /dev/null
else
  warn "dotnet not found — skipping .NET API reference generation."
  warn "Install the .NET SDK (see dotnet/global.json for the pinned version)"
  warn "and run 'dotnet tool restore' in dotnet/ to enable this step."
  # Ensure the output directory exists so MkDocs can still build
  mkdir -p "${DOTNET_API_DIR}"
fi

# ---------------------------------------------------------------------------
# Step 7 — DSC resource documentation
# ---------------------------------------------------------------------------
info "Step 7/9 — DSC resource documentation (DscResource.DocGenerator)"

if command -v pwsh &> /dev/null; then
  pwsh -NonInteractive -File "${DSC_DIR}/build.ps1" \
    -OutputPath "${DOCS_GENERATED_DIR}/dsc-resources"
  success "DSC documentation written to docs/generated/dsc-resources/"
else
  warn "pwsh not found — skipping DSC documentation generation."
  warn "Install PowerShell Core to enable this step: https://aka.ms/install-powershell"
  # Ensure the output directory exists so MkDocs can still build
  mkdir -p "${DOCS_GENERATED_DIR}/dsc-resources"
fi

# ---------------------------------------------------------------------------
# Step 8 — Ansible fact-gather
# ---------------------------------------------------------------------------
info "Step 8/9 — Ansible host fact-gathering"

ansible-playbook \
  -i "${REPO_ROOT}/ansible/inventory.yml" \
  "${REPO_ROOT}/ansible/playbook.yml" \
  --connection=local \
  2>&1 | grep -v "^\[WARNING\]" || true

success "Ansible host report written to docs/generated/"

# ---------------------------------------------------------------------------
# Step 9 — MkDocs build
# ---------------------------------------------------------------------------
info "Step 9/9 — MkDocs build"

mkdocs build --config-file "${MKDOCS_CFG}" --strict

success "MkDocs site built in ${REPO_ROOT}/site/"
echo ""
echo -e "${GREEN}✔ Documentation pipeline completed successfully.${NC}"
echo "  Preview: open ${REPO_ROOT}/site/index.html"

