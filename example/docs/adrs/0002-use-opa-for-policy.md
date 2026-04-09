---
id: ADR-0002
title: Use Open Policy Agent (OPA) for Policy Enforcement
status: Accepted
date: 2024-02-03
author: security-team
tags: [policy, opa, rego, compliance, security]
supersedes: []
related_requirements: [M-002, M-003, S-001, S-002]
---

# ADR-0002 — Use Open Policy Agent (OPA) for Policy Enforcement

## Status

Accepted

## Context

The organization requires automated, pre-deployment compliance verification of
all infrastructure changes.  Specifically:

- Security policies (e.g., "no unencrypted storage") must be enforced as code,
  not checked by human reviewers post-merge.
- FinOps policies (e.g., "all resources must carry cost-allocation tags") must
  block non-compliant pull requests automatically.
- Policy violations must generate actionable, human-readable compliance reports
  that feed into the technical design specification.
- Policies must be unit-testable independently of live infrastructure.

Alternatives evaluated:

| Tool | Pros | Cons |
|------|------|------|
| **OPA + Rego** | CNCF graduated; domain-agnostic; Rego metadata embeds docs; `opa test` for unit tests | Rego learning curve |
| **Checkov** | Python-based; large built-in rule library | Limited custom-policy expressiveness |
| **Sentinel (HashiCorp)** | Native Terraform Cloud integration | Proprietary; tied to HashiCorp ecosystem |
| **Conftest** | OPA wrapper with simpler CLI | Less direct integration with Backstage/MkDocs |

## Decision

Adopt **OPA** (v0.60+) with policies written in **Rego** as the policy
enforcement engine.  Policies live in `policies/terraform/` and are evaluated
against the `terraform plan` JSON output during CI/CD (before `terraform apply`
is permitted).

Key design choices:

1. Every `.rego` file includes a `__rego__metadoc__` block with `id`, `title`,
   `description`, `severity`, and `remediation` fields.  This metadata is
   extracted by the documentation pipeline to generate a compliance chapter in
   the technical design specification automatically.
2. Corresponding `_test.rego` files provide unit tests executed with `opa test`,
   ensuring policy logic is correct before it reaches production.
3. The `deny` rule set is the authoritative contract: a non-empty `deny` set
   causes the CI/CD pipeline to fail and surfaces the denial messages as
   pull-request annotations.

## Consequences

- **Positive:** Compliance checks are deterministic, version-controlled, and
  self-documenting; policy failures block merges automatically; `opa test`
  provides a fast feedback loop.
- **Negative:** Rego requires a learning investment; complex policies can become
  verbose.
- **Future work:** Extend OPA policies to cover Kubernetes manifests and API
  gateway configurations as the platform matures.
