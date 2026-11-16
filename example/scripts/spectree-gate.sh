#!/usr/bin/env bash
# scripts/spectree-gate.sh
#
# SpecTree Validation Gate (issue #26, ADR-0020)
# ==============================================
# Evaluates the OPA validation rules of policies/spectree/validate.rego over
# the normalized traceability metadata contract
# (docs/generated/traceability/metadata-v1.json, ADR-0019) plus the
# solution-manifest ASTs (docs/generated/spectree/*.manifest.ast.json).
#
# ERROR findings fail the gate (exit 1); WARNING findings are surfaced as
# GitHub annotations but do not block — see ADR-0020 for the severity model.
#
# Prerequisites:
#   * scripts/normalize-traceability-metadata.py --all  (metadata artefact)
#   * scripts/spectree-parse.py --all                    (manifest ASTs)
#
# Inputs (environment):
#   OPA   path to the opa binary (default: opa on PATH)
#
# Exit codes
# ----------
#   0 — no ERROR findings (warnings allowed)
#   1 — validation reported ERROR findings, or the input could not be assembled
#
# Usage
# -----
#   bash scripts/spectree-gate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${SCRIPT_DIR}/.."

OPA="${OPA:-opa}"
METADATA="${ROOT}/docs/generated/traceability/metadata-v1.json"
AST_DIR="${ROOT}/docs/generated/spectree"
SPECS_DIR="${ROOT}/spectree/specs"

if [ ! -f "${METADATA}" ]; then
  echo "❌ spectree-gate: ${METADATA} not found — run scripts/normalize-traceability-metadata.py --all first" >&2
  exit 1
fi
if [ ! -d "${AST_DIR}" ]; then
  echo "❌ spectree-gate: ${AST_DIR} not found — run scripts/spectree-parse.py --all first" >&2
  exit 1
fi

GATE_INPUT="$(mktemp /tmp/spectree-gate-input.XXXXXX.json)"
GATE_REPORT="$(mktemp /tmp/spectree-gate-report.XXXXXX.json)"
trap 'rm -f "${GATE_INPUT}" "${GATE_REPORT}"' EXIT

# ── 1. Assemble the gate input (metadata + manifests + spec file list) ───────
python3 - "${METADATA}" "${AST_DIR}" "${SPECS_DIR}" "${GATE_INPUT}" <<'PYEOF'
import glob
import json
import os
import sys

metadata_path, ast_dir, specs_dir, out_path = sys.argv[1:5]

with open(metadata_path, "r", encoding="utf-8") as handle:
    metadata = json.load(handle)

manifests = []
for path in sorted(glob.glob(os.path.join(ast_dir, "*.manifest.ast.json"))):
    with open(path, "r", encoding="utf-8") as handle:
        manifests.append(json.load(handle)["ast"])

spec_files = sorted(
    "spectree/specs/" + name
    for name in os.listdir(specs_dir)
    if os.path.isfile(os.path.join(specs_dir, name))
)

gate_input = {
    "metadata": metadata,
    "manifests": manifests,
    "specFiles": spec_files,
}
with open(out_path, "w", encoding="utf-8") as handle:
    json.dump(gate_input, handle, indent=2, sort_keys=True)
PYEOF

# ── 2. Evaluate the validation rules ─────────────────────────────────────────
"${OPA}" eval \
  --data "${ROOT}/policies/spectree/" \
  --input "${GATE_INPUT}" \
  --format json \
  'data.spectree.validate.report' > "${GATE_REPORT}"

VALID="$(jq -r '.result[0].expressions[0].value.valid' "${GATE_REPORT}")"
ERRORS="$(jq -r '.result[0].expressions[0].value.summary.errors' "${GATE_REPORT}")"
WARNINGS="$(jq -r '.result[0].expressions[0].value.summary.warnings' "${GATE_REPORT}")"
NODES="$(jq -r '.result[0].expressions[0].value.summary.nodes' "${GATE_REPORT}")"
EDGES="$(jq -r '.result[0].expressions[0].value.summary.edges' "${GATE_REPORT}")"

echo "── SpecTree validation gate ────────────────────────────────────────────"
echo "normalized graph: ${NODES} nodes, ${EDGES} edges"
echo "findings: ${ERRORS} error(s), ${WARNINGS} warning(s)"

if [ "$(jq -r '.result[0].expressions[0].value.findings | length' "${GATE_REPORT}")" != "0" ]; then
  echo
  jq -r '.result[0].expressions[0].value.findings[] |
    "  \(.severity) \(.rule): \(.message) (\(.path))"' "${GATE_REPORT}"
  # GitHub annotations (file: the spec source when the finding carries one)
  jq -r '.result[0].expressions[0].value.findings[] |
    if .severity == "ERROR" then "::error title=SPEC-001 \(.rule)::\(.message)"
     else "::warning title=SPEC-001 \(.rule)::\(.message)" end' "${GATE_REPORT}"
fi

echo
if [ "${VALID}" == "true" ]; then
  echo "✅ SpecTree validation gate PASSED — 0 error findings"
  exit 0
fi

echo "❌ SpecTree validation gate FAILED — ${ERRORS} error finding(s)"
exit 1
