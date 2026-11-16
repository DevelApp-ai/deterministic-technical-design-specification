---
id: ADR-0014
title: Use NetArchTest for .NET Architecture Policy Enforcement
status: Accepted
date: 2026-11-16
author: platform-team
tags: [dotnet, netarchtest, policy-as-code, architecture, testing]
supersedes: []
related_requirements: [APP-002, APP-007, M-003]
governs: [dotnet/tests/MyApp.ArchitectureTests/, scripts/generate-dotnet-policy-docs.py, docs/application/architecture-policies.md]
---

# ADR-0014 — Use NetArchTest for .NET Architecture Policy Enforcement

## Status

Accepted

## Context

The pipeline enforces infrastructure rules as policy-as-code — OPA denies a
non-compliant `terraform plan` before anything is applied (ADR-0002).  The
.NET application layer has the same class of rules, expressed in the solution
structure itself:

- Controllers must not depend on repository contracts — all access goes
  through the application service layer.
- The domain layer must stay dependency-free (dependencies flow
  `Api → Application → Domain` only).
- Controllers must expose DTOs, never domain entities.

Without enforcement these rules live in reviewer memory and rot.  They must
become named, machine-checked policies that **block the pipeline before the
documentation build**, mirroring the OPA gate — and, like Rego policies, they
must carry self-describing metadata that a generator can publish to the
compliance pages.

## Decision

Adopt **NetArchTest.Rules** (pinned 1.3.2) in the dedicated test project
`dotnet/tests/MyApp.ArchitectureTests/`:

1. Each policy is declared with `Policy.Define(id, description)` — an id, a
   human description, and named rules per policy — mirroring the
   `__rego__metadoc__` pattern of the OPA policies (APP-007).
2. The test project runs as part of `dotnet test`; a violation fails the
   pipeline before DocFX renders anything from a non-compliant build (APP-002).
3. `scripts/generate-dotnet-policy-docs.py` extracts the policy metadata
   literals from the test source and renders the published catalogue
   `docs/application/architecture-policies.md`, so the compliance page can
   never drift from the enforced rules.
4. Checks NetArchTest cannot express (XML documentation completeness,
   APP-ARCH-003) live as custom xUnit tests in the same project, with the
   same id/description metadata convention.

## Consequences

### Positive

- Architecture rules are executable: violations are red tests, not review
  comments.
- Policy metadata is self-describing and machine-published — the same
  traceability chain as OPA policies (requirement → ADR → policy → docs).
- NetArchTest analyses compiled IL, so it sees the whole solution, not just
  what a single file references.

### Negative / Trade-offs

- NetArchTest only sees method-body IL — `typeof(...)` in attributes is
  invisible to dependency checks, so policies must be written against real
  code paths.
- Policy ids and descriptions are string literals; the generator — not the
  compiler — keeps the published page honest (failures are loud).

## Alternatives Considered

| Alternative | Pros | Cons / Rejected Because |
|-------------|------|------------------------|
| ArchUnitNET | Fluent API, similar rule set | Weaker policy/metadata story; no equivalent of `Policy.Define` |
| NDepend | Powerful, IDE + CI | Commercial licence; queries in a proprietary DSL, not C# |
| Custom Roslyn analyzers only | Compile-time | Architecture rules are solution-wide, not per-file; analyzers cannot see cross-project dependencies |
| No enforcement | None | Rules rot; the layering guarantee the DocFX/OpenAPI pages describe would be aspirational |

## Related

- [ADR-0002 — OPA for Policy](0002-use-opa-for-policy.md)
- [ADR-0016 — Roslyn Analyzer Code-Quality Gate](0016-roslyn-code-quality-gate.md)
- MoSCoW requirements: [APP-002, APP-007](../requirements/moscow.md#must-have)
