---
id: ADR-0011
title: Adopt EU DORA (Digital Operational Resilience Act) Compliance Framework
status: Accepted
date: 2026-04-10
author: security-team
tags: [compliance, dora, ict-risk, resilience, audit, financial]
supersedes: []
related_requirements: [DORA-001, DORA-002, DORA-003, DORA-004, DORA-005, DORA-006, M-003, S-001, NIS2-003, NIS2-005]
---

# ADR-0011 — Adopt EU DORA Compliance Framework

## Status

Accepted

## Context

**EU Regulation 2022/2554 — Digital Operational Resilience Act (DORA)**
applies directly (no national transposition required) to financial entities
and their critical ICT third-party service providers from **17 January 2025**.

DORA establishes uniform requirements across five pillars:

| Chapter | Pillar | Key Articles |
|---------|--------|-------------|
| II | ICT Risk Management | Art.5–16 |
| III | ICT Incident Management, Classification, and Reporting | Art.17–23 |
| IV | Digital Operational Resilience Testing | Art.24–27 |
| V | ICT Third-Party Risk Management | Art.28–44 |
| VI | Information Sharing Arrangements | Art.45 |

**Relationship to NIS2 (ADR-0010):**  
DORA is *lex specialis* over NIS2 for financial entities.  Where both apply,
the more specific DORA obligation takes precedence.  The two frameworks share
overlap on cryptography (Art.9 DORA / Art.21(2)(h) NIS2), incident handling
(Art.17–23 DORA / Art.21(2)(b) NIS2), and business continuity (Art.11–12 DORA
/ Art.21(2)(c) NIS2).  Controls already enforced for NIS2 are credited here.

**Gap identified before this ADR:**

1. No DORA article references in OPA policy `__rego__metadoc__` blocks.
2. No ICT audit-logging enforcement: CloudTrail log-file validation and
   CloudWatch log-group retention are not automated by any existing policy.
3. No S3 bucket-versioning enforcement (DORA Art.12 backup policy).
4. No consolidated DORA audit evidence page.

## Decision

1. **Add `dora` compliance fields** to existing OPA policy `__rego__metadoc__`
   blocks that satisfy DORA obligations, making DORA traceability explicit
   and machine-readable alongside CIS / NIST / SOC2 / NIS2 mappings.

2. **Create `deny_dora_ict_risk.rego`** (policy ID: `DORA-ICT-001`) to enforce
   ICT risk-management and resilience requirements unique to DORA:

   - **Rule 1 — CloudTrail log-file validation** (DORA Art.10 / Art.9):  
     `aws_cloudtrail` resources must have `enable_log_file_validation = true`.
     Log integrity validation detects tampering and satisfies the evidence
     integrity requirement for ICT audit logs.

   - **Rule 2 — CloudWatch log group retention** (DORA Art.10 / Art.15):  
     `aws_cloudwatch_log_group` resources must define an explicit retention
     period (`retention_in_days > 0`).  Indefinite retention (`0`) prevents
     systematic log lifecycle management and may cause evidence to accumulate
     without governance.

   - **Rule 3 — S3 bucket versioning enabled** (DORA Art.12):  
     `aws_s3_bucket_versioning` resources must have `versioning_configuration`
     status set to `"Enabled"`.  Versioning is the minimum prerequisite for a
     DORA-compliant backup policy (point-in-time recovery and accidental
     deletion protection).

3. **Create `docs/compliance/dora.md`** — a structured, audit-ready page
   mapping all five DORA pillars to repository artefacts, including status,
   evidence tables, a gap analysis, and an auditor checklist.

4. **Add DORA requirements** (`DORA-001` through `DORA-006`) to the MoSCoW
   requirements document to maintain the full traceability chain.

5. **Update `docs/security/index.md`** and **`docs/compliance/opa-policies.md`**
   to include a DORA column alongside CIS / NIST / SOC2 / NIS2 mappings.

## Consequences

**Positive:**
- Auditors and supervisory authorities (e.g. ECB SSM, national competent
  authorities) can navigate directly to traceable, code-backed evidence.
- The overlap between DORA and NIS2 is explicitly mapped — existing investment
  in NIS2 controls (SEC-001–006, NIS2-CRYPTO-001) is credited against DORA.
- DORA Art.10 audit-logging enforcement fills the gap noted in the NIS2 gap
  analysis (CloudTrail / AU-2).

**Negative / Trade-offs:**
- DORA Art.25–27 (TLPT — Threat Led Penetration Testing) cannot be automated
  by OPA; it requires an accredited external testing provider.
- DORA Art.28–44 (ICT Third-Party Risk Management) requires contractual and
  due-diligence procedures that are outside the scope of IaC policies.

## Compliance

This ADR directly supports:
- DORA (EU 2022/2554) — Chapters II, III, IV, V, VI
- NIST 800-53 AU-2 (Audit Events) — filled by DORA-ICT-001
- NIST 800-53 CP-9 (Backup) — filled by DORA-ICT-001

## Related ADRs

- [ADR-0002 — Use OPA for Policy](./0002-use-opa-for-policy.md)
- [ADR-0010 — NIS2 Compliance](./0010-nis2-compliance.md)
