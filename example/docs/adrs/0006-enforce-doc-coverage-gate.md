---
id: ADR-0006
title: Enforce Documentation Coverage as a CI Gate
status: Accepted
date: 2024-04-01
author: platform-team
tags: [documentation-as-code, ci-gate, doc-review, quality]
supersedes: []
related_requirements: [M-005, D-001, D-002]
---

# ADR-0006 — Enforce Documentation Coverage as a CI Gate

## Status

Accepted

## Context

The "documentation as code" principle only holds if documentation is
*updated* whenever the code it describes changes.  Without enforcement,
two failure modes emerge:

1. **Silent drift** — a developer changes `terraform/network.tf` but
   forgets to update `docs/network/index.md`.  The site becomes stale
   within one sprint.
2. **Orphaned docs** — a policy is renamed or deleted but the compliance
   page still refers to the old name.

Traditional approaches rely on PR checklist items or reviewer memory.
Neither is reliable, and neither is machine-verifiable.

## Decision

A shell script (`scripts/check-doc-coverage.sh`) is executed as a
dedicated CI job (`doc-coverage`) on every pull request.  The script
compares the files changed in the PR against a set of rules:

| Rule ID  | Code Pattern | Required Doc Pattern |
|----------|-------------|---------------------|
| DOC-TF   | `terraform/*.tf` | `docs/infrastructure/` or `docs/network/` |
| DOC-OPA  | `policies/terraform/*.rego` | `docs/compliance/` or `docs/security/` |
| DOC-DSC  | `dsc/resources/` | `docs/dsc/` |
| DOC-ANS  | `ansible/` | `docs/configuration/` |
| DOC-K8S  | `kubernetes/` | `docs/kubernetes/` |
| DOC-HELM | `helm/` | `docs/kubernetes/` |

If any rule is violated (code changed but no matching doc file touched),
the job fails and the PR cannot be merged.

The script uses `git diff --name-only origin/main HEAD` to identify
changed files, so it works on any PR branch without additional
configuration.

## Consequences

### Positive

- Documentation currency is enforced **automatically** — no reviewer
  memory required.
- The rules are version-controlled alongside the code they govern.
- Easy to extend: add a new rule by appending a `check_rule` call.
- False-positive rate is low: rules only trigger when the specific
  code layer changes; unrelated commits are skipped.

### Negative / Trade-offs

- Adds one extra CI job per PR (~30 s elapsed time).
- Developers must remember to touch at least one doc file when changing
  code; the gate gives a clear error message directing them to the right
  docs path.
- The rule is path-based, not semantic — a one-character whitespace
  change to a doc file satisfies the gate.  Reviewers are still
  responsible for content quality.

## Alternatives Considered

| Alternative | Rejected Because |
|-------------|-----------------|
| PR checklist items | Human error; not machine-enforceable |
| `CODEOWNERS` requiring doc-team review | Slows down every PR; doesn't distinguish code vs. doc changes |
| Lint rules on doc freshness dates | Requires intrusive date stamps on every doc file |

## Related

- [ADR-0003 — MkDocs for Publishing](0003-use-mkdocs-for-publishing.md)
- MoSCoW requirements: [D-001, D-002](../requirements/moscow.md#should-have--documentation-governance)
