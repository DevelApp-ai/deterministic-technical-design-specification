---
id: ADR-0021
title: SpecTree Line Grammar for the TDS Composition Manifest
status: Accepted
date: 2026-11-16
author: platform-team
tags: [spectree, tds, composition, grammar, determinism, mkdocs, techdocs, git-blob-sha]
supersedes: []
related_requirements: [S-006, M-005]
governs: [spectree/tds/, spectree/schemas/tds-manifest-v1.schema.json, scripts/generate-tds-composition.py, docs/generated/tds/, docs/traceability/tds-composition.md]
---

# ADR-0021 — SpecTree Line Grammar for the TDS Composition Manifest

## Status

Accepted

## Context

Issue #25 asks for the **TDS composition manifest**: a deterministic
declaration of *which sources assemble into which Technical Design
Specification* — sections in order, per-section sources (file globs, AST
node selectors), a version bound to source versions for reproducible
rebuilds, rendering targets (MkDocs, Backstage TechDocs, standalone
export), and inclusion/exclusion rules (Won't requirements summarized
rather than detailed, superseded ADRs in an appendix).

The estate already composes the document *implicitly*: the MkDocs nav in
`mkdocs.yml` (ADR-0003) orders the pages, the traceability graph
(ADR-0019) holds the node inventory, and the SpecTree grammars (ADR-0018)
parse the specification sources — but nothing *declares* the composition
as data, so the assembled TDS cannot be rebuilt, diffed, or exported from
a manifest.

Three decisions were open in the issue:

1. **Manifest format** — YAML (consistent with `mkdocs.yml` and
   Backstage) or a SpecTree format itself (`.tds`), defined in
   Minotaur-Grammars?
2. **Scope** — one TDS per solution, per repository, or per system?
3. **Nav** — does the manifest *replace* `mkdocs.yml`, or *generate* it?

## Decision

1. **Format: a SpecTree line grammar (`.tds`), not YAML.**  The
   composition manifest is specification content, not tool configuration,
   and it must meet the determinism bar of ADR-0018: **standard library
   only, no third-party parsers**.  YAML would have pulled PyYAML into
   every environment that validates the manifest (the traceability CI
   job, local workstations, the docs Docker image), breaking the
   zero-dependency property every other gate in this repo keeps.  A
   line grammar parses with the same ~100 lines of stdlib Python as the
   other SpecTree grammars, stays diffable line-by-line in code review,
   and carries a machine-readable published contract: the parsed shape
   is published as
   `spectree/schemas/tds-manifest-v1.schema.json` (the ADR-0019
   precedent — **contracts live in this repo**).  Upstreaming the grammar
   definition into Minotaur-Grammars is proposed once it stabilizes; the
   grammar is *defined here first*, and — deliberately — *not* folded
   into `scripts/spectree-parse.py`: that parser's grammar registry maps
   1:1 to the eight vendored Minotaur-Grammars grammars and its
   selftest count is cited in ADR-0018/README; composition is a
   different lifecycle (document assembly, not spec ingestion) and gets
   its own tool, `scripts/generate-tds-composition.py`, with its own
   selftest.

2. **Scope: one TDS per solution.**  The composition unit is the
   *solution* — the same unit the SolutionManifest
   (`spectree/specs/myapp.manifest`, ADR-0018) binds projects to specs,
   the same unit the .NET workload builds, and the same unit Backstage
   models as a component.  `spectree/tds/myapp.tds` binds to
   `myapp.manifest` through the required `## Solution:` directive, which
   the generator verifies exists.  A repository *may* carry multiple TDS
   manifests (one per solution) — the generator composes every
   `spectree/tds/*.tds` it finds; per-system aggregation is a publishing
   concern of the targets, not of the manifest.

3. **The manifest generates the composition bindings; `mkdocs.yml` keeps
   the publishing configuration.**  The generator resolves every source
   glob against the tree and emits a **committed, drift-gated
   composition report** (`docs/generated/tds/myapp.composition.json`)
   binding each composed file to its **git blob SHA** — computed in pure
   Python (`sha1("blob <len>\0" + bytes)`, identical to
   `git hash-object`), so the report is byte-identical on every machine
   and proves that a rebuilt TDS assembled from exactly the audited
   inputs.  The manifest does **not** rewrite `mkdocs.yml` (ADR-0003
   keeps publishing config — theme, plugins, strict mode); instead the
   generator **verifies** the declared `mkdocs (nav: …)` anchor exists
   in `mkdocs.yml`, so manifest and nav cannot drift silently, and the
   nav stays hand-reviewable YAML.

**Grammar** (annotated reference: `spectree/tds/myapp.tds`):

```text
# TDS: <title>                      required, exactly one
## Solution: <manifest-file-name>    required; spectree/specs/<name>
## Version: <semver>                 required; TDS document version
## Target: <kind> (key: value, ...)  repeatable; mkdocs | techdocs | standalone
### Section: <title>                 repeatable, ordered, unique
- Source: <glob>                     repeatable, >=1 per section
- Source: <glob> (generated)         pipeline artefact: declared, never
                                     blob-bound (integrity derives from
                                     the deterministic build, ADR-0013/0015)
- Selector: <artefact>#<node-type>   AST node selector, resolved with counts
- Rule: <phrase>                     fixed vocabulary:
                                     summarize wont requirements,
                                     appendix superseded adrs,
                                     exclude deprecated adrs,
                                     detail public api,
                                     exclude test projects
```

Sources marked `(generated)` (the DocFX API reference, the OpenAPI
document) are **declared but never blob-bound**: they do not exist in a
fresh checkout until the pipeline stage that produces them has run, and
their content integrity is already guaranteed transitively — they are
deterministic functions of blob-bound sources (ADR-0013, ADR-0015).
Binding their SHAs would make the report differ between environments and
break the drift gate.

## Consequences

### Positive

- The assembled TDS is now *data*: sections, sources, selectors, rules,
  targets — parseable, validatable, diffable, and exportable.
- Every composed page carries its git blob SHA in the committed report:
  a deterministic rebuild from the same tree provably assembles the same
  document.
- Inclusion/exclusion rules move from prose (issue #25) into a fixed,
  validated vocabulary the generator enforces.
- The mkdocs nav anchor check catches composition/nav drift at gate
  time, not site-build time.
- The generator is stdlib-only with a 38-check selftest, mirroring the
  spectree-parse/normalize tooling bar.

### Negative / Trade-offs

- A second grammar to learn — mitigated by the published JSON Schema and
  the annotated reference manifest.
- Rule phrases are declarative composition directives; their rendering
  semantics (e.g. how "summarize wont requirements" shapes a page) are
  documentation conventions today, enforced by review, not yet by a
  rendering gate.
- The committed report must be regenerated whenever any composed file
  changes — the same drift-gate discipline as the catalog, drawio, and
  metadata artefacts.

## Alternatives Considered

| Alternative | Pros | Cons / Rejected Because |
|-------------|------|------------------------|
| YAML manifest | Familiar; mkdocs/Backstage native | PyYAML dependency in every validating environment breaks the ADR-0018 stdlib bar; composition is spec content, not tool config |
| Extend `spectree-parse.py` with a ninth grammar | One parser | Couples the vendored-grammar registry to a repo-local grammar; churns the cited selftest count; mixes ingestion with composition lifecycles |
| One TDS per repository | Fewest manifests | Repositories may host several solutions; the solution is the unit the SolutionManifest, the build, and Backstage already model |
| Manifest generates/rewrites `mkdocs.yml` nav | Single source | Generated YAML churns ADR-0003-governed publishing config; harder to review than a verified anchor |
| Blob-bind generated artefacts too | Stronger report | Files absent in fresh checkouts → report differs per environment → drift gate unusable; integrity already derives from deterministic builds |

## Related

- [ADR-0003 — MkDocs for Publishing](0003-use-mkdocs-for-publishing.md)
- [ADR-0013 — DocFX for .NET API Reference](0013-docfx-dotnet-api-reference.md)
- [ADR-0015 — Native .NET OpenAPI Generation](0015-native-dotnet-openapi.md)
- [ADR-0018 — SpecTree Specification-First Ingestion](0018-spectree-specification-first-ingestion.md)
- [ADR-0019 — Shared Traceability Metadata Contract](0019-shared-traceability-metadata-contract.md)
- [ADR-0020 — SpecTree Validation Gate](0020-spectree-validation-gate.md)
