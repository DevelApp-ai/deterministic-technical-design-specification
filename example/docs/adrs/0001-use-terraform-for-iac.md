---
id: ADR-0001
title: Use Terraform as the Primary Infrastructure Provisioning Tool
status: Accepted
date: 2024-01-15
author: platform-team
tags: [iac, terraform, provisioning]
supersedes: []
related_requirements: [M-001, M-004, M-006]
---

# ADR-0001 — Use Terraform as the Primary Infrastructure Provisioning Tool

## Status

Accepted

## Context

The organization requires a single, declarative Infrastructure as Code (IaC)
tool to provision and manage cloud and on-premises resources across multiple
environments (dev, staging, prod).  The tool must:

- Support multi-cloud deployments (AWS, Azure, GCP).
- Produce a machine-readable execution plan suitable for automated OPA policy
  evaluation before any change is applied.
- Integrate with CI/CD pipelines and auto-generate human-readable documentation
  without manual effort.
- Have broad community adoption, a large provider ecosystem, and long-term
  vendor support.

Alternatives evaluated:

| Tool | Pros | Cons |
|------|------|------|
| **Terraform (HCL)** | Mature, multi-cloud, graph-based dependency resolution, `terraform plan` JSON output for OPA, `terraform-docs` for auto-docs | HashiCorp BSL licence change in v1.6 |
| **OpenTofu** | FOSS fork of Terraform, MPL-2.0 licence, API-compatible | Smaller community, fewer provider certifications |
| **Pulumi** | General-purpose languages (Python, TypeScript) | No built-in plan-JSON for OPA; docs generation immature |
| **AWS CloudFormation** | Native AWS, no provider drift | AWS-only; no cross-cloud support |

## Decision

Adopt **Terraform** (≥ 1.5, HashiCorp BSL) as the primary IaC provisioning
tool for Day-0 infrastructure.  The `local` provider is used in this example
repository to allow the full toolchain to execute without cloud credentials.

Terraform fulfils the documentation-pipeline mandate because:

1. `terraform plan -out plan.bin && terraform show -json plan.bin` produces a
   deterministic JSON artefact that OPA policies evaluate before `apply`.
2. `terraform-docs` parses `variables.tf` and `outputs.tf` to auto-generate a
   Markdown README, eliminating hand-written input/output tables.
3. The `.tfstate` file can be ingested by diagramming tools (e.g., Infragram)
   to deterministically render C4-model architecture diagrams.

## Consequences

- **Positive:** Single source of truth for infrastructure; documentation is
  generated, never hand-written; OPA gates prevent non-compliant changes.
- **Negative:** Teams must learn HCL syntax; state file management requires a
  remote backend (S3 + DynamoDB or Terraform Cloud) for team collaboration.
- **Risk:** HashiCorp BSL licence may restrict certain commercial use cases —
  monitor OpenTofu migration path as mitigation.
