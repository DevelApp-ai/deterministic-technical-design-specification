---
id: ADR-0019
title: Use a Shared Traceability Metadata Contract for All Spec Sources
status: Accepted
date: 2026-11-16
author: platform-team
tags: [traceability, metadata, id-namespaces, json-schema, normalizer, specTree, determinism]
supersedes: []
related_requirements: [S-006, M-005]
governs: [spectree/schemas/, spectree/id-namespaces.json, scripts/normalize-traceability-metadata.py, docs/generated/traceability/, docs/traceability/metadata-contract.md]
---

# ADR-0019 — Use a Shared Traceability Metadata Contract for All Spec Sources

## Status

Accepted

## Context

The pipeline now ingests specifications from four format families, each with
its own metadata conventions:

* Markdown — MoSCoW requirement tables (`docs/requirements/moscow.md`) and
  ADR YAML front-matter (`related_requirements`, `supersedes`, `governs`).
* Rego — `__rego__metadoc__` blocks with `related_adr`,
  `related_requirements`, and a `compliance` map (NIS2/DORA article refs).
* SpecTree — the eight grammars ingested by `scripts/spectree-parse.py`
  (ADR-0018), whose ASTs carry compliance links
  (`requirementLinks`/`adrReferences`, `requirementCoverage`, ADR
  `relatedRequirements`) in yet another shape.
* .NET — architecture policy IDs (`APP-ARCH-00x`, `APP-SEC-00x`) defined as
  literals in `MyApp.ArchitectureTests`.

The ADR Traceability Kit (ADR-0012) already assembles part of this chain
(catalog + `traceability.drawio`), and issue #29's program requires the whole
chain — including the SpecTree layer — to be machine-readable *as one
graph*.  But there is no published contract for what a "traceability node"
is, where its id namespace ends, or how the three metadata dialects map onto
each other.  Worse, ids collide across sources: `M-001` denotes a MoSCoW
infrastructure requirement in `moscow.md` and a functional requirement in
`spectree/specs/myapp.srs`, so raw ids cannot be used as graph keys.

Issue #24 therefore asks for one shared metadata & ID contract: a common id
scheme with namespaces and mechanical uniqueness, cross-reference fields on
every spec node, compliance metadata equivalent to the Rego
`__rego__metadoc__.compliance` block, a published JSON Schema, and a
normalizer that maps all sources onto that shape.

## Decision

Publish **one versioned, schema-validated contract** for the normalized
traceability graph, with four namespace-qualified id spaces:

1. **ID registry — `spectree/id-namespaces.json`.**  Every id in the graph
   is `<namespace>:<local-id>` with four namespaces: `moscow:` (Markdown
   MoSCoW tables), `spec:` (SpecTree SRS/AI/Test/NS nodes), `adr:` (ADR
   decisions, Markdown and `AdrSpec` merged by id), and `policy:` (OPA
   policy metadocs, including the .NET architecture policy IDs mirrored
   into policies).  The registry lists the accepted local-id prefixes per
   namespace and the resolution rule for each cross-reference field, so a
   Markdown `related_requirements` entry resolves to the `moscow:` namespace
   while a SpecTree `requirementLinks` entry resolves to `spec:`.

2. **JSON Schema — `spectree/schemas/traceability-metadata-v1.schema.json`.**
   The envelope (`schema`, `schemaVersion`, `generated`, `nodes`, `edges`,
   `integrity`) with one `$def` per node type (requirement, ADR, policy,
   component, test-suite, NFR, system), a fixed edge-type enum
   (references, implements, satisfies, covers, supersedes, traces), and an
   integrity section (duplicate ids, dangling edges).  The contract is
   versioned (`schemaVersion: 1`) and lives in *this* repository — the
   upstream Minotaur-Grammars repository keeps the grammars only, so the
   contract can evolve at pipeline cadence without cross-repo coupling.

3. **Normalizer — `scripts/normalize-traceability-metadata.py`.**  A
   stdlib-only, deterministic CLI (same bar as ADR-0012/0018) that reads the
   four source families through the committed scanners and parsers
   (`scan-architecture.py`, `spectree-parse.py`), maps them onto the
   schema, and writes the committed, drift-gated artefact
   `docs/generated/traceability/metadata-v1.json`.  Duplicate node ids
   **fail the build**; cross-references that point at ids no source defines
   are *recorded* (not fatal) in `integrity.danglingEdges`, because
   referential policy (e.g. "every satisfied requirement must exist")
   belongs to the OPA validation gate (issue #26), not to normalization.

4. **Legacy sources are normalized, not migrated.**  The Markdown and Rego
   sources stay authoritative where they are; the normalizer maps them
   indefinitely.  No front-matter keys, metadoc fields, or SpecTree
   grammars change shape for this contract.

Compliance metadata (`framework`, `refs`, `description`) is carried on every
node type that can declare it, mirroring `__rego__metadoc__.compliance`:
policy nodes get it from the Rego metadoc block, system/NFR nodes from the
`.ns` grammar's compliance and security sections.

## Consequences

### Positive

- One graph over four format families: downstream consumers (drift gate,
  issue #26's OPA referential gate, issue #21's traceability matrix) read a
  single schema-validated document instead of four dialects.
- Namespace qualification removes the `M-001` collision between
  `moscow.md` and `myapp.srs`; ids are now globally unique graph keys.
- Mechanical uniqueness: the normalizer fails loudly on duplicates, so the
  registry is enforced by CI, not by review discipline.
- The published JSON Schema is the durable contract for external
  consumers; versioned independently of the vendored grammars.
- Byte-deterministic output (sorted nodes/edges, no timestamps) — the same
  bar as the architecture catalog, verified by the drift gate.

### Negative / Trade-offs

- Two Markdown sources of truth remain for requirements (moscow.md tables
  and the SRS); the contract records both faithfully but does not unify
  them — that is deliberate (normalization, not migration) and revisitable.
- Dangling references are recorded rather than rejected; until issue #26
  lands, a dangling edge is visible in `integrity.danglingEdges` but does
  not fail the build.
- The schema uses the stdlib-only validator subset already pinned by
  ADR-0018 (type, required, properties, enum, oneOf, `$defs`, arrays) — no
  exotic JSON-Schema keywords.

## Alternatives Considered

| Alternative | Pros | Cons / Rejected Because |
|-------------|------|------------------------|
| Migrate all sources to SpecTree grammars | One format to parse | Large migration churn in governed docs/policies for no contract benefit; legacy sources are already gated and readable |
| Publish the contract from Minotaur-Grammars | Co-located with grammars | Cross-repo release coupling; the contract describes pipeline artefacts this repo owns |
| Flat (unqualified) ids | Simpler strings | `M-001` collides between moscow.md and myapp.srs; the whole graph keys on ids, so collisions are fatal |
| Fail the build on dangling references inside the normalizer | Strongest integrity | Referential rules (which edges *must* resolve) are policy — issue #26's OPA gate — not normalization; recording keeps the two concerns separable |

## Related

- [ADR-0012 — Machine-Readable ADR Traceability Kit](0012-machine-readable-adr-traceability.md)
- [ADR-0018 — SpecTree Specification-First Ingestion](0018-spectree-specification-first-ingestion.md)
- [ADR-0003 — MkDocs for Publishing](0003-use-mkdocs-for-publishing.md)
- MoSCoW requirements: [S-006, M-005](../requirements/moscow.md)
- Metadata contract page: [Metadata Contract](../traceability/metadata-contract.md)
