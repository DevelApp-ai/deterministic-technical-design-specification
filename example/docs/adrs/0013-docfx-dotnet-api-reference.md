---
id: ADR-0013
title: Use DocFX for .NET API Reference Generation
status: Accepted
date: 2026-11-16
author: platform-team
tags: [dotnet, docfx, api-reference, documentation-as-code]
supersedes: []
related_requirements: [APP-001, M-004]
governs: [dotnet/docs/, dotnet/dotnet-tools.json, docs/generated/dotnet-api/]
---

# ADR-0013 — Use DocFX for .NET API Reference Generation

## Status

Accepted

## Context

The deterministic documentation pipeline auto-generates reference
documentation for every code layer: `terraform-docs` for Terraform modules,
`DscResource.DocGenerator` for DSC resources, OPA metadocs for policies.  The
.NET application layer introduced the same obligation: hand-written API
reference tables would violate the pipeline's core rule (documentation is
generated, never hand-maintained).

The substrate was already in place — the deterministic build gate raises
CS1591 on any undocumented public member, so every compiled assembly ships a
complete XML documentation file.  What was missing was the renderer that
turns those XML files into a published, MkDocs-consumable API reference.

## Decision

Adopt **DocFX** (pinned to 2.81.0 in the local tool manifest
`dotnet/dotnet-tools.json`, `rollForward: false`) as the .NET API reference
generator:

1. `dotnet/docs/docfx.json` configures `docfx metadata` with the experimental
   **Markdown output format**, emitting straight to
   `docs/generated/dotnet-api/` — one MkDocs page per namespace, no
   intermediate HTML site.
2. `dotnet/docs/filter.yml` keeps the top-level-statement `Program` class out
   of the generated surface.
3. The generator runs in `scripts/generate-docs.sh` Step 5, **after** the
   build gate (warnings-as-errors, Roslyn analyzers, NetArchTest policies)
   has passed — documentation is only generated from a compliant build.
4. Output is a git-ignored, deterministic pipeline artefact, re-rendered on
   every pipeline run; the MkDocs nav publishes the namespace pages under the
   Application section.

## Consequences

### Positive

- The API reference cannot drift from the code — it is regenerated from the
  compiled assemblies' XML docs on every run.
- Pinned tool versions keep the output byte-reproducible (verified: identical
  output across repeated runs).
- No new server or runtime: DocFX is a local .NET tool, restored from the
  committed manifest.

### Negative / Trade-offs

- The Markdown export is an **experimental** DocFX format; format changes may
  require re-pinning on upgrade (mitigated by `rollForward: false` and the
  determinism check).
- DocFX is a heavyweight tool for a small API surface; the pipeline accepts
  that cost for output fidelity.

## Alternatives Considered

| Alternative | Pros | Cons / Rejected Because |
|-------------|------|------------------------|
| Sandcastle | Long-standing, XML-doc native | Effectively unmaintained; HTML output only |
| Swagger UI / OpenAPI only | Already generated (ADR-0015) | Covers endpoints, not the full type/namespace surface |
| Hand-written API reference | None | Violates the documentation-as-code principle; drifts immediately |
| Source-generated docs (custom Roslyn) | Fully controllable | Large build effort to re-invent what DocFX already does |

## Related

- [ADR-0003 — MkDocs for Publishing](0003-use-mkdocs-for-publishing.md)
- [ADR-0015 — Native .NET OpenAPI Generation](0015-native-dotnet-openapi.md)
- MoSCoW requirements: [APP-001](../requirements/moscow.md#must-have)
