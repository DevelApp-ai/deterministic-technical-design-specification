#!/usr/bin/env bash
# check-doc-coverage.sh
#
# PR Documentation Coverage Gate
# ================================
# Fails the build when "code" files are modified in a PR/push without a
# corresponding documentation file also being touched.
#
# Rules enforced
# --------------
# 1. terraform/    → at least one file under docs/infrastructure/ or docs/network/
# 2. policies/     → at least one file under docs/compliance/ or docs/security/
# 3. dsc/resources/→ at least one file under docs/dsc/
# 4. ansible/      → at least one file under docs/configuration/
# 5. kubernetes/   → at least one file under docs/kubernetes/
# 6. helm/         → at least one file under docs/kubernetes/
#
# Usage
# -----
#   # Compare HEAD against main (CI usage)
#   BASE_BRANCH=main bash scripts/check-doc-coverage.sh
#
#   # Compare two explicit refs
#   BASE_REF=abc123 HEAD_REF=def456 bash scripts/check-doc-coverage.sh
#
# Exit codes
# ----------
#   0 — all rules satisfied
#   1 — at least one rule violated

set -euo pipefail

BASE_BRANCH="${BASE_BRANCH:-main}"
BASE_REF="${BASE_REF:-}"
HEAD_REF="${HEAD_REF:-HEAD}"

# ── Collect changed files ─────────────────────────────────────────────────────
if [[ -n "${BASE_REF}" ]]; then
  CHANGED=$(git diff --name-only "${BASE_REF}" "${HEAD_REF}" 2>/dev/null || true)
else
  # Attempt to diff against remote base branch; fall back to last commit
  git fetch origin "${BASE_BRANCH}" --quiet 2>/dev/null || true
  if git rev-parse "origin/${BASE_BRANCH}" &>/dev/null; then
    CHANGED=$(git diff --name-only "origin/${BASE_BRANCH}" "${HEAD_REF}" 2>/dev/null || true)
  else
    CHANGED=$(git diff --name-only HEAD~1 HEAD 2>/dev/null || true)
  fi
fi

if [[ -z "${CHANGED}" ]]; then
  echo "ℹ️  No changed files detected — nothing to check."
  exit 0
fi

echo "── Changed files ────────────────────────────────────────────────────────"
echo "${CHANGED}" | sed 's/^/  /'
echo "─────────────────────────────────────────────────────────────────────────"

# ── Helper: does the changed-file list match a glob pattern? ─────────────────
changed_in() {
  echo "${CHANGED}" | grep -qE "$1"
}

# ── Rule evaluation ───────────────────────────────────────────────────────────
VIOLATIONS=0

check_rule() {
  local rule_id="$1"
  local code_pattern="$2"
  local doc_pattern="$3"
  local description="$4"

  if changed_in "${code_pattern}"; then
    if changed_in "${doc_pattern}"; then
      echo "✅ ${rule_id}: ${description} — docs updated"
    else
      echo "❌ ${rule_id}: ${description}"
      echo "   Code changes matched: ${code_pattern}"
      echo "   Expected doc changes matching: ${doc_pattern}"
      VIOLATIONS=$((VIOLATIONS + 1))
    fi
  else
    echo "⏭️  ${rule_id}: ${description} — no code changes (skipped)"
  fi
}

check_rule "DOC-TF"  \
  "example/terraform/.*\\.tf$" \
  "example/docs/(infrastructure|network)/" \
  "Terraform changes must be accompanied by docs/infrastructure/ or docs/network/ updates"

check_rule "DOC-OPA" \
  "example/policies/terraform/[^_].*\\.rego$" \
  "example/docs/(compliance|security)/" \
  "OPA policy changes must be accompanied by docs/compliance/ or docs/security/ updates"

check_rule "DOC-DSC" \
  "example/dsc/resources/" \
  "example/docs/dsc/" \
  "DSC resource changes must be accompanied by docs/dsc/ updates"

check_rule "DOC-ANS" \
  "example/ansible/" \
  "example/docs/configuration/" \
  "Ansible changes must be accompanied by docs/configuration/ updates"

check_rule "DOC-K8S" \
  "example/kubernetes/" \
  "example/docs/kubernetes/" \
  "Kubernetes manifest changes must be accompanied by docs/kubernetes/ updates"

check_rule "DOC-HELM" \
  "example/helm/" \
  "example/docs/kubernetes/" \
  "Helm chart changes must be accompanied by docs/kubernetes/ updates"

echo "─────────────────────────────────────────────────────────────────────────"

if [[ "${VIOLATIONS}" -gt 0 ]]; then
  echo "❌ Documentation coverage gate FAILED — ${VIOLATIONS} rule(s) violated."
  echo "   Update the relevant docs/ page(s) alongside your code changes."
  exit 1
else
  echo "✅ Documentation coverage gate PASSED — all rules satisfied."
  exit 0
fi
