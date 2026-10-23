#!/usr/bin/env bash
# scripts/architecture-gate.sh
#
# ADR Boundary Gate (ADR-0012)
# ==============================
# Fails a pull request whose change set touches a path governed by an
# Accepted ADR when the PR description cites none of the governing ADRs
# (id format ADR-####).  Also rejects links to superseded ADRs — the
# finding names the current successor — and links to ADR ids that do not
# exist.
#
# Pipeline:
#   1. scan-architecture.py  — regenerate docs/generated/architecture-catalog.json
#   2. validate.rego         — the catalog itself must be coherent
#   3. gate.rego             — catalog + changedPaths + adrLinks -> report
#
# Inputs (environment):
#   BASE_BRANCH  base branch to diff against (default: main)
#   PR_BODY      pull request description; ADR ids cited in it are the links
#
# Exit codes
# ----------
#   0 — no governed path changed, or every governed change has its ADR linked
#   1 — validate or gate reported ERROR findings
#
# Usage
# -----
#   BASE_BRANCH=main PR_BODY="Refs ADR-0012" bash scripts/architecture-gate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${SCRIPT_DIR}/.."

BASE_BRANCH="${BASE_BRANCH:-main}"
PR_BODY="${PR_BODY:-}"

CATALOG="${ROOT}/docs/generated/architecture-catalog.json"
GATE_INPUT="$(mktemp)"
trap 'rm -f "${GATE_INPUT}"' EXIT

# ── 1. Regenerate the catalog (deterministic; no timestamps) ──────────────────
python3 "${SCRIPT_DIR}/scan-architecture.py" --root "${ROOT}"

# ── 2. The catalog itself must validate before it can gate anything ───────────
echo "── ADR catalog validation ──────────────────────────────────────────────"
opa eval \
  --data "${ROOT}/policies/architecture/" \
  --input "${CATALOG}" \
  --format pretty \
  'data.architecture.validate.report' > /tmp/adr62-validate.json

if [ "$(jq -r '.valid' /tmp/adr62-validate.json)" != "true" ]; then
  echo "❌ ADR catalog validation FAILED — the gate cannot run on an incoherent catalog:"
  jq -r '.findings[] | "   \(.severity) \(.rule): \(.message) (\(.path))"' /tmp/adr62-validate.json
  exit 1
fi
echo "✅ catalog valid — $(jq -r '.scan.adr_count' "${CATALOG}") ADRs, $(jq -r '.scan.policy_count' "${CATALOG}") policies, $(jq -r '.scan.requirement_count' "${CATALOG}") requirements, 0 findings"

# ── 3. Collect the change set (paths relative to example/) ────────────────────
if git rev-parse --git-dir > /dev/null 2>&1; then
  git fetch origin "${BASE_BRANCH}" --quiet 2>/dev/null || true
  if git rev-parse "origin/${BASE_BRANCH}" &>/dev/null; then
    CHANGED=$(git diff --name-only "origin/${BASE_BRANCH}" HEAD 2>/dev/null || true)
  else
    CHANGED=$(git diff --name-only HEAD~1 HEAD 2>/dev/null || true)
  fi
else
  CHANGED=""
fi

# The gate's governs patterns are example/-relative; diff paths are repo-relative.
CHANGED=$(echo "${CHANGED}" | grep -v '^$' | sed 's|^example/||' || true)

# ── 4. Extract the ADR ids cited in the PR description ───────────────────────
LINKS=$(echo "${PR_BODY}" | grep -oE 'ADR-[0-9]{4}' | sort -u || true)

echo "── Boundary gate ────────────────────────────────────────────────────────"
if [ -z "${CHANGED}" ]; then
  echo "ℹ️  No changed files detected — nothing to gate."
  exit 0
fi
echo "Changed paths (example/-relative):"
echo "${CHANGED}" | sed 's/^/  /'
if [ -n "${LINKS}" ]; then
  echo "Linked ADRs (from PR description):"
  echo "${LINKS}" | sed 's/^/  /'
else
  echo "Linked ADRs: (none cited in the PR description)"
fi

# ── 5. Merge catalog + change set into the gate input ────────────────────────
export CATALOG GATE_INPUT CHANGED LINKS
python3 - <<'PYEOF'
import json, os

with open(os.environ["CATALOG"], encoding="utf-8") as fh:
    catalog = json.load(fh)

changed = [l for l in os.environ.get("CHANGED", "").splitlines() if l.strip()]
links = [l for l in os.environ.get("LINKS", "").splitlines() if l.strip()]

catalog["changedPaths"] = sorted(changed)
catalog["adrLinks"] = sorted(links)

with open(os.environ["GATE_INPUT"], "w", encoding="utf-8") as fh:
    json.dump(catalog, fh, indent=2)
PYEOF

# ── 6. Evaluate the gate ─────────────────────────────────────────────────────
opa eval \
  --data "${ROOT}/policies/architecture/" \
  --input "${GATE_INPUT}" \
  --format pretty \
  'data.architecture.gate.report' > /tmp/adr62-gate.json

if [ "$(jq -r '.valid' /tmp/adr62-gate.json)" != "true" ]; then
  echo "❌ ADR boundary gate FAILED:"
  jq -r '.findings[] | "   \(.severity) \(.rule): \(.message) (\(.path))"' /tmp/adr62-gate.json
  exit 1
fi

echo "✅ ADR boundary gate PASSED — every governed change cites its ADR."
