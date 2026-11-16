---
id: ADR-0022
title: Filtered .NET API Export from Build-Time XML Doc Comments
status: Accepted
date: 2026-11-16
author: platform-team
tags: [dotnet, xml-doc-comments, api-export, traceability, spectree, determinism, tds]
supersedes: []
related_requirements: [APP-001, M-001, M-002, S-002]
governs: [scripts/generate-dotnet-doc-export.py, docs/generated/tds/dotnet-api/, docs/generated/tds/dotnet-spec-mapping.json]
---

# ADR-0022 — Filtered .NET API Export from Build-Time XML Doc Comments

## Status

Accepted

## Context

Issue #27 asks for application-layer documentation export: the .NET
solution's XML doc comments rendered as deterministic Markdown for TDS
inclusion, with filtering (public API surface only, exclusions for test
projects, generated code, and internal helpers), selective inclusion of
`<remarks>`/`<exception>`/`<example>` elements, and mapping of code
elements back to spec ids "so application code nodes join the
traceability graph".

The estate already publishes an exhaustive API reference through DocFX
(ADR-0013, `docs/generated/dotnet-api/`) and an OpenAPI document at
build time (ADR-0015).  Neither is *filtered for the TDS*: DocFX exports
everything with template-level control only, and neither carries
code→requirement traceability.  The TDS composition manifest (ADR-0021)
declares composition rules (`detail public api`, `exclude test
projects`) with no tool implementing them.

Four decisions were open in the issue:

1. **Renderer** — DocFX template customization, a Roslyn-based
   extractor, or a tool over the build artifacts?
2. **Traceability mechanism** — handwritten `<spec>` XML doc tags
   (drift risk if unchecked) vs. generated attributes?
3. **Where do filtering rules live** — per-project policy docs,
   conventions in code, or the manifest?
4. **Is the export committed and drift-gated, or CI-generated?**

## Decision

1. **Renderer: a stdlib-Python tool over the compiler's XML doc files.**
   `scripts/generate-dotnet-doc-export.py` parses the XML documentation
   files the build already emits (`GenerateDocumentationFile`,
   ADR-0016) — no second compiler pass, no DocFX template surgery, no
   new toolchain dependency (the ADR-0018 determinism bar: standard
   library only).  DocFX remains the exhaustive reference (ADR-0013);
   this export is the *filtered* TDS view.

2. **Traceability: handwritten `<spec>` tags, machine-verified.**  A
   `<spec>moscow:M-001</spec>` XML doc tag on a type or member declares
   the requirement it traces to (namespace-qualified id per
   `spectree/id-namespaces.json`).  The drift risk the issue called out
   is closed by verification, not generation: **every `<spec>` id is
   checked against the node ids of the committed
   `docs/generated/traceability/metadata-v1.json`** (ADR-0019), and an
   unknown id fails the export in CI.  Generated attributes would have
   added source noise without adding verification the tags lack.

3. **Filtering rules live in the tool, implementing the ADR-0021
   manifest vocabulary.**  The manifest *declares intent* (`detail
   public api`, `exclude test projects`); the tool *implements policy*:
   the public surface comes for free from the XML doc files themselves
   (the compiler emits entries only for members visible outside their
   assembly — CS1591 plus `TreatWarningsAsErrors` already force complete
   public documentation); test projects are never scanned
   (`dotnet/src/` only, `*Tests*` assemblies rejected defensively); the
   `MyApp.Api.Infrastructure` namespace (DI plumbing) is excluded;
   `summary`, `remarks`, `param`, `returns`, `exception`, `response`,
   and `spec` elements render, everything else is skipped.  Inline
   references (`<see>`, `<paramref>`) render in short form without
   truncating their sentences.

4. **The export and the mapping artefact are CI-generated, declared
   `(generated)` in the manifest — not committed, not drift-gated.**
   They derive from build output that does not exist in a fresh
   checkout, so they cannot pass a kit-job drift gate; instead the
   docs job regenerates them after the .NET build, byte-identically
   (deterministic rendering, no timestamps), and *verification runs
   there*: `<spec>` ids that do not resolve in the metadata contract
   fail the pipeline.  The mapping
   (`docs/generated/tds/dotnet-spec-mapping.json`, schema
   `dotnet-spec-mapping-v1`) is the machine-readable code→spec edge
   the traceability graph consumes: 7 members, 10 spec references
   across the three application assemblies today.

## Consequences

### Positive

- The TDS gains a filtered, deterministic, human-readable view of the
  application's public API — distinct from the exhaustive DocFX
  reference and the HTTP-level OpenAPI view.
- Application code now carries *verified* bidirectional traceability:
  the SRS traces `M-001 → TodoService.cs`; the export traces
  `TodoService → moscow:M-001` — and a typo in either direction fails
  CI.
- `<spec>` tags double as review surface: a member whose trace is
  missing is visible in the diff and in the mapping artefact.
- Zero new dependencies: reuses the compiler's own doc output and the
  stdlib-only generator pattern of ADR-0018/0021.

### Negative / Trade-offs

- The export only exists after a Release build — the kit job cannot
  render it; consumers must use the docs job (or run
  `dotnet build MyApp.slnx -c Release` then the tool).
- Record positional parameters are documented on the type, constructor,
  and property by the compiler; the export shows all three, which is
  mildly repetitive (fidelity over curation).
- The filtering policy is fixed in the tool today; richer per-section
  policy would extend the manifest rule vocabulary (ADR-0021) rather
  than invent a second config surface.

## Alternatives Considered

| Alternative | Pros | Cons / Rejected Because |
|-------------|------|------------------------|
| DocFX template customization | One renderer | Filtering + `<spec>` semantics not expressible in templates; exhaustive export ≠ TDS view |
| Roslyn-based extractor | Full semantic model (visibility, attributes) | Second compiler pass, new tooling in the docs job; the XML doc files already carry exactly the public surface |
| Generated traceability attributes | No hand-written tags | Source noise; still needs the same CI verification; tags are more reviewable in doc comments |
| Commit + drift-gate the export | Gate in the kit job | Derived from build output absent in fresh checkouts → unusable drift gate (same reasoning as ADR-0021's `(generated)` sources) |
| Filter via per-project policy docs | Local control | A second config surface duplicating what the ADR-0021 manifest already declares |

## Related

- [ADR-0013 — DocFX for .NET API Reference](0013-docfx-dotnet-api-reference.md)
- [ADR-0015 — Native .NET OpenAPI Generation](0015-native-dotnet-openapi.md)
- [ADR-0016 — Roslyn Code-Quality Gate](0016-roslyn-code-quality-gate.md)
- [ADR-0019 — Shared Traceability Metadata Contract](0019-shared-traceability-metadata-contract.md)
- [ADR-0021 — SpecTree Line Grammar for the TDS Composition Manifest](0021-tds-composition-manifest-grammar.md)
