---
id: ADR-0010
title: Adopt NIS2 Compliance Framework for Security Controls Documentation
status: Accepted
date: 2026-04-10
author: security-team
tags: [compliance, nis2, security, policy, audit]
supersedes: []
related_requirements: [NIS2-001, NIS2-002, NIS2-003, NIS2-004, NIS2-005, NIS2-006, M-003, S-001, CYB-002, CYB-003, CYB-004]
---

# ADR-0010 — Adopt NIS2 Compliance Framework for Security Controls Documentation

## Status

Accepted

## Context

The EU **Network and Information Security Directive 2** (NIS2 — Directive
2022/2555) took effect in EU Member States from **17 October 2024**.  It
expands the scope of mandatory cybersecurity obligations to a significantly
larger set of essential and important entities and prescribes specific
technical and organisational security measures under **Article 21**.

The organisation must:

1. Demonstrate that **all ten Article 21(2) measures** are in place before
   an audit or supervisory inspection.
2. Evidence must be **traceable, current, and machine-verifiable** — a static
   Word document submitted annually is insufficient.
3. Existing security controls (OPA policies, Terraform modules, Ansible
   hardening playbooks, DSC resources) should be mapped to NIS2 measures to
   avoid duplication and prove existing investment.

Key NIS2 Article 21(2) measures and their relevance to this repository:

| Measure | Description | Current Coverage |
|---------|-------------|-----------------|
| (a) | Risk analysis and information system security policies | ADRs + MoSCoW requirements |
| (b) | Incident handling | Operational runbook |
| (c) | Business continuity, backup, DR | `storage.tf` backup bucket + monitoring alarms |
| (d) | Supply chain security | W-001 (out of scope — local provider demo) |
| (e) | Security in acquisition, development, and maintenance | OPA gate + CI/CD pipeline |
| (f) | Effectiveness assessment of risk management | OPA test suite + doc coverage gate |
| (g) | Cyber hygiene and training | Onboarding guide + Ansible hardening |
| (h) | Cryptography and encryption | SEC-001, SEC-006, new NIS2-CRYPTO-001 policy |
| (i) | Human resources security, access control, asset management | SEC-003 (IAM), FINOPS-001 (tags) |
| (j) | MFA and secured communications | SEC-005 (HTTPS), SEC-006 (TLS 1.2+) |

**The gap identified before this ADR** was that:
- Existing OPA policies did **not** carry NIS2 article references in their
  `__rego__metadoc__` blocks, making traceability opaque to auditors.
- KMS key rotation (NIS2 Art.21.2h) and RDS encryption-at-rest were not
  enforced by any policy.
- No consolidated audit page existed linking all controls to NIS2 evidence.

## Decision

1. **Add `nis2` compliance fields** to all existing OPA policy `__rego__metadoc__`
   blocks so that compliance reports and the audit page carry explicit NIS2 article
   references alongside CIS/NIST/SOC2 mappings.

2. **Create `deny_nis2_crypto.rego`** (policy ID: `NIS2-CRYPTO-001`) to enforce
   the cryptography and key-management requirements of NIS2 Art.21(2)(h):
   - AWS KMS keys must have key rotation enabled.
   - AWS RDS instances must have storage encryption enabled.
   - AWS SSM Parameter Store entries with secret-like names must use
     `SecureString` type (not plaintext `String`).

3. **Create `docs/compliance/nis2.md`** — a structured, audit-ready page that
   maps every NIS2 Article 21(2) measure to the concrete evidence artefacts
   in this repository, including status (Automated / Documented / Partial / Gap)
   and direct links.

4. **Add NIS2 requirements** (`NIS2-001` through `NIS2-006`) to the MoSCoW
   requirements document so that the traceability chain runs all the way from
   NIS2 obligation to OPA enforcement.

5. **Update `docs/security/index.md`** and **`docs/compliance/opa-policies.md`**
   to include a NIS2 column alongside existing CIS / NIST / SOC2 mappings.

## Consequences

**Positive:**
- Auditors can verify compliance by reading a single URL and following evidence
  links, rather than reviewing multiple disconnected documents.
- NIS2 traceability is automated: changes to OPA policies update the compliance
  report automatically via the CI/CD pipeline.
- Existing security investments are clearly credited against specific NIS2
  article obligations.
- The gap analysis on `nis2.md` provides a living roadmap for the security team.

**Negative / Trade-offs:**
- Adding `nis2` fields to existing `.rego` files is a minor change that
  increases metadoc verbosity.
- NIS2 Art.21(2)(d) (supply chain security) and full Art.21(2)(g) (training)
  cannot be automated by OPA alone; documentary evidence must supplement code.

## Compliance

This ADR directly supports:
- NIS2 Directive (EU 2022/2555) — Article 21 obligations
- NIS2 Art.21(2)(f): Effectiveness assessment of risk-management measures
- NIST 800-53 PL-1 (Security Planning Policy and Procedures)

## Related ADRs

- [ADR-0002 — Use OPA for Policy](./0002-use-opa-for-policy.md) — the policy
  engine whose metadocs this ADR extends.
