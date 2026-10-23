#!/usr/bin/env bash
# scripts/architecture-demo.sh
#
# ADR Traceability Kit — end-to-end demo (ADR-0012)
# =================================================
# Proves the done-when scenario of the traceability kit with inverted
# expectations: every step asserts the outcome it must produce, including
# the steps that must FAIL.  opa eval always exits 0, so every verdict is
# asserted on the JSON report itself (jq -e), never on exit codes.
#
#   (a) the real catalog scans and validates clean
#   (b) a boundary change with no linked ADR is BLOCKED — the finding
#       cites the governing ADR
#   (c) the same change with the governing ADR cited in the PR
#       description PASSES
#   (d) a link to a superseded ADR is REJECTED — the finding names the
#       current successor resolved by the chain traversal
#   (e) a broken catalog (cycle, dangling requirement, unknown ADR link)
#       is REJECTED by validation with loud findings
#   (f) the chain traversal resolves a three-link supersede chain to its
#       terminal ADR
#   (g) the traceability diagram regenerates byte-identically
#
# Usage:
#   bash scripts/architecture-demo.sh
#
# Exit code 0 — every step produced its expected outcome.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${SCRIPT_DIR}/.."
FIXTURES="${SCRIPT_DIR}/architecture-demo-fixtures"
OPA="${OPA:-opa}"

CATALOG="${ROOT}/docs/generated/architecture-catalog.json"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

PASSED=0

step() { echo; echo "── [demo] $1 ─────────────────────────────────────────"; }

# Assert a jq expression over a JSON file (jq -e: exit 0 only when the
# expression evaluates to a truthy value).
assert_jq() {
  local label="$1" expr="$2" file="$3"
  if jq -e "${expr}" "${file}" > /dev/null 2>&1; then
    echo "✅ ${label}"
    PASSED=$((PASSED + 1))
    return 0
  fi
  echo "❌ ${label}"
  return 1
}

# Evaluate a Rego query over a JSON input into a raw-JSON output file.
eval_json() {
  local input_file="$1" query="$2" out="$3"
  "${OPA}" eval \
    --data "${ROOT}/policies/architecture/" \
    --input "${input_file}" \
    --format raw \
    "${query}" > "${out}"
}

# Merge the real catalog with a fixture change set -> gate input JSON.
merge_changes() {
  local changes="$1" out="$2"
  python3 - "${CATALOG}" "${changes}" "${out}" <<'PYEOF'
import json, sys

with open(sys.argv[1], encoding="utf-8") as fh:
    catalog = json.load(fh)
with open(sys.argv[2], encoding="utf-8") as fh:
    changes = json.load(fh)

catalog["changedPaths"] = sorted(changes["changedPaths"])
catalog["adrLinks"] = sorted(changes["adrLinks"])

with open(sys.argv[3], "w", encoding="utf-8") as fh:
    json.dump(catalog, fh, indent=2)
PYEOF
}

# ---------------------------------------------------------------------------
step "(a) the real catalog scans and validates clean"
# ---------------------------------------------------------------------------

python3 "${SCRIPT_DIR}/scan-architecture.py" --root "${ROOT}"
eval_json "${CATALOG}" 'data.architecture.validate.report' "${TMP}/validate.json"
assert_jq "catalog valid — 0 findings" \
  '.valid == true and .finding_count == 0' "${TMP}/validate.json"

# ---------------------------------------------------------------------------
step "(b) a boundary change with no linked ADR is BLOCKED"
# ---------------------------------------------------------------------------

merge_changes "${FIXTURES}/changes-no-links.json" "${TMP}/gate-blocked.json"
eval_json "${TMP}/gate-blocked.json" 'data.architecture.gate.report' "${TMP}/gate-blocked-out.json"
assert_jq "gate blocks terraform/main.tf with no ADR link" \
  '.valid == false' "${TMP}/gate-blocked-out.json"
assert_jq "finding cites gate/boundary-change-without-adr and the governing ADR-0001" \
  '.findings | map(select(.rule == "gate/boundary-change-without-adr" and ((.message | contains("ADR-0001"))))) | length > 0' \
  "${TMP}/gate-blocked-out.json"
jq -r '.findings[] | "     \(.rule): \(.message)"' "${TMP}/gate-blocked-out.json"

# ---------------------------------------------------------------------------
step "(c) the same change with the governing ADR cited PASSES"
# ---------------------------------------------------------------------------

merge_changes "${FIXTURES}/changes-with-link.json" "${TMP}/gate-pass.json"
eval_json "${TMP}/gate-pass.json" 'data.architecture.gate.report' "${TMP}/gate-pass-out.json"
assert_jq "gate passes terraform/main.tf when ADR-0001 is cited" \
  '.valid == true and .finding_count == 0' "${TMP}/gate-pass-out.json"

# ---------------------------------------------------------------------------
step "(d) a superseded ADR link is REJECTED and redirected to the successor"
# ---------------------------------------------------------------------------

eval_json "${FIXTURES}/supersede-catalog.json" 'data.architecture.gate.report' "${TMP}/gate-superseded.json"
assert_jq "gate rejects the superseded ADR-0001 link" \
  '.valid == false' "${TMP}/gate-superseded.json"
assert_jq "the finding redirects to the current successor ADR-0003" \
  '.findings | map(select(.rule == "gate/superseded-adr-link" and ((.message | contains("ADR-0003"))))) | length > 0' \
  "${TMP}/gate-superseded.json"
jq -r '.findings[] | "     \(.rule): \(.message)"' "${TMP}/gate-superseded.json"

# ---------------------------------------------------------------------------
step "(e) a broken catalog is REJECTED with loud findings"
# ---------------------------------------------------------------------------

eval_json "${FIXTURES}/broken-catalog.json" 'data.architecture.validate.report' "${TMP}/validate-broken.json"
assert_jq "validate rejects the broken fixture catalog" \
  '.valid == false' "${TMP}/validate-broken.json"
for RULE in catalog/supersede-cycle catalog/dangling-requirement-ref catalog/policy-unknown-adr; do
  assert_jq "${RULE} flagged" \
    ".findings | map(select(.rule == \"${RULE}\")) | length > 0" "${TMP}/validate-broken.json"
done
jq -r '.findings[] | "     \(.rule): \(.message) (\(.path))"' "${TMP}/validate-broken.json"

# ---------------------------------------------------------------------------
step "(f) the chain traversal resolves a three-link chain to its terminal"
# ---------------------------------------------------------------------------

eval_json "${FIXTURES}/supersede-catalog.json" 'data.architecture.chain.effective' "${TMP}/effective.json"
assert_jq "effective[ADR-0001] = ADR-0003 (0003 supersedes 0002 supersedes 0001)" \
  '.["ADR-0001"] == "ADR-0003"' "${TMP}/effective.json"

# ---------------------------------------------------------------------------
step "(g) the traceability diagram regenerates byte-identically"
# ---------------------------------------------------------------------------

python3 "${SCRIPT_DIR}/generate-traceability.py" --root "${ROOT}"
python3 "${SCRIPT_DIR}/generate-traceability.py" --root "${ROOT}" --check
cp "${ROOT}/docs/generated/traceability.drawio" "${TMP}/diagram-1.drawio"
python3 "${SCRIPT_DIR}/generate-traceability.py" --root "${ROOT}" > /dev/null
if cmp -s "${TMP}/diagram-1.drawio" "${ROOT}/docs/generated/traceability.drawio"; then
  echo "✅ regenerated diagram is byte-identical"
  PASSED=$((PASSED + 1))
else
  echo "❌ diagram regeneration is not deterministic"
  exit 1
fi

# ---------------------------------------------------------------------------
echo
echo "── demo complete: ${PASSED} steps produced their expected outcome ──────"
