---
id: ADR-0018
title: Use SpecTree Specification-First Ingestion for the Documentation Pipeline
status: Accepted
date: 2026-11-16
author: platform-team
tags: [spectree, specification-first, parsers, documentation-as-code, determinism, traceability]
supersedes: []
related_requirements: [S-006, M-005]
governs: [spectree/, scripts/spectree-parse.py, docs/generated/spectree/]
---

# ADR-0018 — Use SpecTree Specification-First Ingestion for the Documentation Pipeline

## Status

Accepted

## Context

The pipeline's traceability chain currently starts at *artefacts that already
exist*: MoSCoW tables, ADR front-matter, Rego metadocs, .NET policy IDs.
Everything upstream of those — the stakeholder requests, functional
requirements, API contracts, test matrices that motivated the work — lives
only in human prose that no gate can read.

The [SpecTree](https://github.com/DevelApp-ai/Minotaur-Grammars)
specification-first format family (SRS, AI, Test, API, Model, NS, ADR, and
Solution-Manifest grammars) closes that gap: specifications are written in a
small line-based EBNF grammar, so they are reviewable as text *and*
machine-parseable.  The missing piece in this repository is the ingestion
layer: deterministic parsers that turn those specifications into JSON ASTs
the pipeline can validate and render.

Two properties are non-negotiable, mirroring the rest of the estate:

1. **Determinism** — parsing the same tree twice must produce byte-identical
   output (the architecture catalog, ADR-0012, already holds this bar).
2. **No silent degradation** — an unparseable specification must fail loudly
   with file, line, and expected/actual tokens.

## Decision

Adopt SpecTree as the specification-first input layer, ingested by **one
deterministic, stdlib-only Python CLI**, `scripts/spectree-parse.py`:

1. **Grammar provenance** — the eight grammar files are vendored under
   `spectree/grammars/`, pinned to Minotaur-Grammars commit
   `de45cd55169d`.  The grammars are documentation of the accepted syntax;
   the parser is line-based and does not read them at runtime (no runtime
   dependency on the external repository).

2. **Parser surface** — the CLI parses all eight grammars
   (`SrsSpec`, `AiSpec`, `TestSpec`, `ApiSpec`, `ModelSpec`, `NsSpec`,
   `AdrSpec`, `SolutionManifest`), each into a typed AST document.  A
   `--selftest` mode runs the full negative/positive fixture suite
   (120 checks); `--all` parses every spec under `spectree/specs/`; `--spec`
   parses a single file.  Unknown extensions and malformed lines fail with
   file:line diagnostics and a non-zero exit.

3. **AST contract** — every output is a versioned envelope:
   `{schema: "spectree-ast", schemaVersion: 1, astType, source: {path,
   grammar, grammarCommit}, ast}`.  The contract is committed as a JSON
   Schema (2020-12) at `spectree/schemas/spectree-ast-v1.schema.json`, and
   the CLI embeds a minimal validator that checks every emitted AST against
   it before writing — an AST that cannot be validated is never produced.

4. **Output territory** — ASTs are written to
   `docs/generated/spectree/<name>.ast.json` and are **git-ignored** (like all
   `docs/generated/` artefacts they are rebuild outputs, not sources); the
   committed schema is the durable contract.  Sample specifications mirroring
   the real MyApp solution live under `spectree/specs/` and serve as the
   pipeline's living fixtures.

5. **Pipeline wiring** — `scripts/generate-docs.sh` (Step 5) runs
   `--selftest` then `--all` so a broken parser or specification fails the
   docs build; the CI `docs-build` job runs the same step.

## Consequences

### Positive

- Specifications become first-class pipeline inputs: the traceability chain
  can now start at requirements-level text, not at rendered artefacts.
- Byte-identical ASTs across runs (verified by md5 across repeated runs) —
  the same bar the architecture catalog holds.
- Stdlib-only Python: no runtime dependencies to pin, no network access at
  parse time, runnable in the existing CI image.
- The `AdrSpec` format gives ADRs a machine-parseable twin, and the
  `SolutionManifest` format binds projects to the specs and generators that
  consume them — the composition layer for later issues.
- Negative fixtures in `--selftest` keep the error paths as tested as the
  happy path.

### Negative / Trade-offs

- Eight grammars vendored is eight surfaces to re-pin when
  Minotaur-Grammars evolves; the pinned commit is recorded in each AST's
  `source.grammarCommit`, so provenance is always visible.
- A line-based EBNF cannot express every specification style; complex prose
  stays in companion Markdown documents.
- The embedded JSON-Schema validator is a minimal subset (type, required,
  properties, enum, oneOf, `$defs`, arrays) — deliberate, to stay
  stdlib-only; exotic schema keywords would require a full `jsonschema`
  dependency.

## Alternatives Considered

| Alternative | Pros | Cons / Rejected Because |
|-------------|------|------------------------|
| Parse specs with a general grammar tool (ANTLR/lark) | Full EBNF fidelity | Non-stdlib runtime dependency; grammar-tool version pinning; overkill for line-based grammars |
| Hand-write one parser per grammar as separate CLIs | Smaller units | Eight entry points, eight behaviours to keep consistent; one CLI keeps the envelope contract uniform |
| YAML/JSON specs instead of SpecTree grammars | Off-the-shelf parsing | Loses the human-reviewable line format and the SpecTree cross-repo standard |
| Generate ASTs at build time only, no committed schema | Less to maintain | No durable contract for downstream consumers; AST shape could drift silently between runs |

## Related

- [ADR-0003 — MkDocs for Publishing](0003-use-mkdocs-for-publishing.md)
- [ADR-0012 — Machine-Readable ADR Traceability Kit](0012-machine-readable-adr-traceability.md)
- MoSCoW requirements: [S-006, M-005](../requirements/moscow.md)
- Grammar source: <https://github.com/DevelApp-ai/Minotaur-Grammars> (commit `de45cd55169d`)
