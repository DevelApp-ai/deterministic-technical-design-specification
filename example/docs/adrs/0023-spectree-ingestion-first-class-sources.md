---
id: ADR-0023
title: SpecTree Ingestion as First-Class TDS Sources
status: Accepted
date: 2026-11-16
author: platform-team
tags: [spectree, ingestion, vendoring, coexistence, traceability, determinism]
supersedes: []
related_requirements: [S-006, M-005, APP-001]
governs: [spectree/specs/]
---

# ADR-0023 — SpecTree Ingestion as First-Class TDS Sources

## Status

Accepted

## Context

Issue #22 asked the pipeline to ingest the SpecTree grammar formats
(`.srs`, `.adr`, `.ai`, `.test`, `.model`, `.api`, `.ns`, solution
manifest) as **first-class TDS sources**, extending the traceability
chain from the infrastructure layer
(MoSCoW → ADR → OPA policy → Terraform) to the application layer:
**requirement (`.srs`) → decision (`.adr`) → component (`.ai`) → test
(`.test`) → application code (.NET)**.

The capability sub-issues have all shipped: parsers (ADR-0018), the
shared metadata contract (ADR-0019), the OPA validation gate
(ADR-0020), the TDS composition manifest grammar (ADR-0021), and the
filtered .NET API export with `<spec>` traceability (ADR-0022).  Three
decisions in the issue remained open, and they govern the shape of the
ingestion surface:

1. **Repository split** — are SpecTree grammars/parsers owned by
   Minotaur-Grammars and only consumed here, or do parsers live in this
   repo?  (Affects versioning and release coupling.)
2. **Coexistence or replacement** — do SpecTree files replace the
   Markdown MoSCoW/ADR formats over time, or run in parallel?
3. **File sourcing** — same repo, git submodule, NuGet-published AST
   JSON, or CI artifact fetch?

## Decision

1. **Grammars are version-pinned vendored snapshots; parsers live in
   this repo.**  Minotaur-Grammars owns the grammar *definitions*
   (issues #93–#101); this repo vendors them under `spectree/grammars/`
   at a pinned snapshot and implements the parsers in
   `scripts/spectree-parse.py` (stdlib-only, selftested, ADR-0018).
   Release coupling is deliberate and one-directional: upstream grammar
   changes enter only through an explicit vendor bump + parser update
   in the same PR — nothing breaks silently on an upstream push, and
   `main` stays green.  Repo-local grammar concepts (the `.tds`
   composition manifest, ADR-0021) are defined here first, with
   upstreaming to Minotaur-Grammars proposed after stabilisation — the
   same contracts-live-here precedent ADR-0019 set.

2. **Coexistence, not replacement.**  SpecTree files run alongside the
   Markdown MoSCoW/ADR formats, normalized onto **one** metadata
   contract (ADR-0019) with namespace-qualified ids — `moscow:M-001`
   and `spec:M-001` can never collide.  Markdown remains the source of
   truth for MoSCoW priorities and ADR prose (the formats the estate
   already reviews in every PR); SpecTree adds the machine-precision
   layers Markdown cannot express: components, test suites, NFRs,
   measurable `.ns` bounds, and the solution manifest binding projects
   to specs.  Any future migration is data-driven, not
   decree-driven: the normalizer's resolution rules absorb a format
   family moving wholesale to SpecTree without downstream changes.

3. **Same repository, in-tree: `spectree/specs/`.**  Spec files are
   first-class repo content — reviewable in the same PR as the code
   they specify, versioned by the same commits, parsed by the same CI
   job.  Rejected alternatives all break the determinism bar: a git
   submodule makes fresh-checkout state depend on a second remote;
   NuGet-published AST JSON inserts a release pipeline (and versioning
   skew) between specification and code; a CI artifact fetch couples
   every build to another pipeline's availability and retention.

**The chain is closed end to end.**  With this ADR the issue's
capability table is fully green:

| Capability | Delivered by |
|------------|--------------|
| SpecTree parsers → JSON ASTs | `scripts/spectree-parse.py` (ADR-0018) |
| Shared metadata & id contract | `docs/generated/traceability/metadata-v1.json` (ADR-0019) |
| Validation gate over spec ASTs | `policies/spectree/validate.rego`, `SPEC-001` (ADR-0020) |
| TDS composition manifest | `spectree/tds/myapp.tds` + composition report (ADR-0021) |
| Application-layer doc export | `scripts/generate-dotnet-doc-export.py` (ADR-0022) |
| Application code in the traceability graph | `<spec>` tags verified against the contract (ADR-0022) |

Application code joins the graph through the **verified mapping
artefact** (`dotnet-spec-mapping-v1`, ADR-0022) rather than by
extending the metadata contract with api-member node types: metadata v1
stays schema-stable, and a v2 extension is deferred until a consumer
actually needs member-level graph queries — contract changes are
versioned, never improvised (ADR-0019).

## Consequences

### Positive

- The traceability chain now spans both layers:
  `myapp.srs → .adr/.ai/.test → .NET members → moscow: requirements`,
  every hop machine-verified in CI.
- The repo's ingestion surface is stable and auditable: vendor bumps
  are explicit, parsers are selftested, formats coexist under one
  contract.
- No external runtime dependencies: no submodule state, no package
  feed, no cross-pipeline fetch.

### Negative / Trade-offs

- Grammar fixes flow only as fast as deliberate vendor bumps — the
  same coupling that protects `main`.
- Two requirement families mean two review habits; the namespaced
  contract keeps them coherent but reviewers must still read both.
- Member-level application code is not yet a *node type* in the
  graph — it is a verified mapping beside it.  Consumers wanting
  single-artifact member queries wait for a v2 contract.

## Alternatives Considered

| Alternative | Pros | Cons / Rejected Because |
|-------------|------|------------------------|
| Parsers owned + published by Minotaur-Grammars | One owner | Release coupling in the wrong direction: every CI run depends on an upstream publish; parser bugs fixable only upstream |
| Replace Markdown MoSCoW/ADR with SpecTree | One format | Loses the review-friendly prose formats; massive migration churn for no contract gain — normalization already unifies them |
| Git submodule for spec files | Upstream editing | Fresh-checkout determinism depends on a second remote; spec/code reviews split across repos |
| NuGet-published AST JSON | Reusable across repos | Version skew between spec and code; a release pipeline between writing and parsing |
| CI artifact fetch | No repo coupling | Every build coupled to another pipeline's availability and retention window |

## Related

- [ADR-0018 — SpecTree Specification-First Ingestion](0018-spectree-specification-first-ingestion.md)
- [ADR-0019 — Shared Traceability Metadata Contract](0019-shared-traceability-metadata-contract.md)
- [ADR-0020 — SpecTree Validation Gate](0020-spectree-validation-gate.md)
- [ADR-0021 — SpecTree Line Grammar for the TDS Composition Manifest](0021-tds-composition-manifest-grammar.md)
- [ADR-0022 — Filtered .NET API Export from Build-Time XML Doc Comments](0022-xml-doc-filtered-api-export.md)
