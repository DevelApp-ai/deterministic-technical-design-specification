---
id: ADR-0020
title: Use an OPA Validation Gate over the SpecTree Metadata Contract
status: Accepted
date: 2026-11-16
author: platform-team
tags: [spectree, opa, rego, validation-gate, severity-model, traceability, ci]
supersedes: []
related_requirements: [S-006, M-005]
governs: [policies/spectree/, scripts/spectree-gate.sh]
---

# ADR-0020 — Use an OPA Validation Gate over the SpecTree Metadata Contract

## Status

Accepted

## Context

The infrastructure pipeline proves every merge against OPA policy
(`policies/terraform/`, ADR-0002): violations block the pipeline, findings
cite rule names and paths, and the rules themselves are unit-tested as
`*_test.rego`.  Specification content has no equivalent guarantee: the
SpecTree grammars (ADR-0018) parse deterministically and the shared metadata
contract (ADR-0019) normalizes all four source families into one graph — but
nothing *evaluates rules over that graph*.

Issue #26 asks for exactly that: the validation rules from
Minotaur-Grammars #94–#101 (one MoSCoW value per requirement, Must coverage,
no premature implementation of Won't work, acyclic dependencies, no orphan
manifest projects, no references to missing or non-accepted ADRs, measurable
`.ns` bounds, requirement↔component completeness) enforced in CI, blocking
PRs that violate them, with denial messages citing spec file and node id,
and unit tests for the rules.

Two decisions were open in the issue:

1. **Engine** — OPA/Rego (consistent with the pipeline, new input shape) or
   .NET-native validation (shared codebase with the application layer)?
2. **Severity model** — are all violations merge-blocking, or do some
   degrade to warnings?

## Decision

1. **Engine: OPA/Rego over the ADR-0019 metadata contract.**  The gate
   (`policies/spectree/validate.rego`, policy id `SPEC-001`) evaluates rules
   over `docs/generated/traceability/metadata-v1.json` plus the
   solution-manifest ASTs — the input shape ADR-0019 reserved for exactly
   this purpose ("referential rules belong to the OPA validation gate,
   issue #26").  Rego keeps the rule language uniform with the rest of the
   estate, the OPA binary is already installed in the CI job, and rules are
   unit-tested in `policies/spectree/validate_test.rego` with the same
   `opa test` convention as the architecture kit.  The wrapper
   `scripts/spectree-gate.sh` assembles the gate input deterministically and
   fails with non-zero exit on ERROR findings; a .NET validator would have
   required the .NET toolchain in the traceability job and invented a second
   rule language.

2. **Severity model: two levels, split by kind, not by rule list.**
   * **ERROR (merge-blocking)** — contradictions and broken structural
     invariants: duplicate node ids, manifest specs that do not exist,
     orphan manifest projects, dependency cycles, references to missing,
     non-Accepted, or Superseded ADRs, and non-measurable `.ns` bounds.
     These are unambiguous defects: the same tree can never satisfy them
     under a different reading.
   * **WARNING (surfaced as GitHub annotations, non-blocking)** —
     completeness and maturity gaps: Must requirements without test
     coverage, test suites covering undeclared requirements, components
     satisfying only Won't requirements (premature implementation),
     dependencies without component specs, requirements without components
     and vice versa, and `.ns` constraints without an ADR trace.  The
     current corpus carries 15 such warnings — real, visible gaps that are
     being closed incrementally; blocking on them would make `main` red on
     the day the gate ships, which teaches teams to ignore gates.

   The split is recorded in the policy header so new rules declare their
   severity with their rationale.  Warnings can be promoted to errors
   opportunistically as the corpus closes its gaps.

## Consequences

### Positive

- Specification content now holds the same bar as infrastructure content:
  violations block merges with findings that cite the spec file, node id,
  rule name, and JSON path.
- The gate consumes the published ADR-0019 contract, not raw parser ASTs —
  one input shape for every downstream consumer, as designed.
- Rule unit tests (`opa test policies/spectree/`) keep the fail paths as
  tested as the happy path: 19 tests cover every rule firing and the clean
  input producing zero findings.
- The gate doubles as a live gap report: the warning list is the
  traceability backlog.

### Negative / Trade-offs

- Warnings do not block; a team that ignores annotations can merge with
  completeness debt.  The promotion path mitigates this.
- The gate depends on two generated artefacts (metadata + manifest ASTs)
  being current; the CI drift gate already enforces exactly that.
- `graph.reachable`-based cycle detection requires care (the builtin
  includes the start set in its result); the rule walks from direct targets
  and the unit test pins that behaviour.

## Alternatives Considered

| Alternative | Pros | Cons / Rejected Because |
|-------------|------|------------------------|
| .NET-native validation (Roslyn/MSBuild) | Shared codebase with parsers | Requires the .NET toolchain in the traceability job; a second rule language beside Rego; rules not reviewable as policies |
| All violations merge-blocking | Simplest severity story | The corpus ships with genuine completeness gaps; `main` would be red, breeding gate blindness |
| No severity split — only blocking rules, subset that passes today | Fewer moving parts | Silent about the gaps the issue explicitly wants surfaced (Must coverage, premature implementation) |
| Validate raw parser ASTs instead of the metadata contract | No normalizer dependency | Four format dialects in the rules; re-implements the cross-format joins ADR-0019 already provides |

## Related

- [ADR-0002 — OPA for Policy](0002-use-opa-for-policy.md)
- [ADR-0012 — Machine-Readable ADR Traceability Kit](0012-machine-readable-adr-traceability.md)
- [ADR-0018 — SpecTree Specification-First Ingestion](0018-spectree-specification-first-ingestion.md)
- [ADR-0019 — Shared Traceability Metadata Contract](0019-shared-traceability-metadata-contract.md)
- MoSCoW requirements: [S-006, M-005](../requirements/moscow.md)
- Contract page: [Metadata Contract](../traceability/metadata-contract.md)
