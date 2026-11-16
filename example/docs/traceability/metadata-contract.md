# Traceability Metadata Contract

Since [ADR-0019](../adrs/0019-shared-traceability-metadata-contract.md), the
traceability graph is assembled through **one shared, versioned metadata
contract** instead of per-format conventions.  This page documents that
contract: the id namespaces, the node and edge shapes, the resolution rules,
and how to regenerate the normalized artefact.

## The normalized artefact

[`docs/generated/traceability/metadata-v1.json`](../generated/traceability/metadata-v1.json)
is the single machine-readable graph over **all four spec source families**:

| Source family | Examples | Nodes produced |
|---------------|----------|----------------|
| Markdown MoSCoW tables | `docs/requirements/moscow.md` | `moscow:*` requirements |
| Markdown ADR front-matter | `docs/adrs/*.md` | `adr:*` decisions |
| Rego metadocs | `policies/**/*.rego` (`__rego__metadoc__`) | `policy:*` policies with compliance metadata |
| SpecTree grammars | `spectree/specs/*.srs/.ai/.test/.ns/.adr` | `spec:*` requirements, components, test-suites, NFRs, systems |

The artefact is **committed and drift-gated**: CI regenerates it via
`scripts/normalize-traceability-metadata.py` and fails if the committed file
differs — the same bar the [architecture catalog](index.md) holds.

## ID namespaces

Every node id is namespace-qualified (`<namespace>:<local-id>`) so that
identical local ids from different sources can never collide — `M-001` is
`moscow:M-001` in the requirements table and `spec:M-001` in the SRS:

| Namespace | Local-id prefixes (examples) | Sources |
|-----------|------------------------------|---------|
| `moscow:` | `M-`, `APP-`, `S-`, `A-`, `CYB-`, `OPS-`, `DEV-`, `DORA-`, `NIS2-`, `FIN-`, `K-`, `V-`, `W-` | Markdown MoSCoW tables |
| `spec:` | `REQ-`, `M-`, `PERF-`, `SCAL-`, `SEC-`, `<Component>`, `<Component>.tests` | SpecTree grammars |
| `adr:` | `ADR-0000`…`ADR-9999` | Markdown ADRs and `AdrSpec` files (merged by id) |
| `policy:` | `ARCH-`, `SC-`, `FINOPS-`, `K8S-`, `NIS2-CRYPTO-`, `DORA-ICT-` | Rego metadocs, .NET architecture policy ids |

The authoritative registry is
[`spectree/id-namespaces.json`](https://github.com/DevelApp-ai/deterministic-technical-design-specification/blob/main/example/spectree/id-namespaces.json),
which also records the **resolution rules** for every cross-reference field:
Markdown `related_requirements` and Rego `related_requirements` resolve into
the `moscow:` namespace; SpecTree `requirementLinks` / `requirementCoverage`
resolve into `spec:`; ADR references resolve into `adr:`.

## Envelope, nodes, and edges

The document shape is defined by the published JSON Schema
[`spectree/schemas/traceability-metadata-v1.schema.json`](https://github.com/DevelApp-ai/deterministic-technical-design-specification/blob/main/example/spectree/schemas/traceability-metadata-v1.schema.json)
(versioned as `traceability-metadata` v1):

- **Envelope** — `schema`, `schemaVersion`, `generated`, `nodes`, `edges`,
  `integrity`.
- **Node types** — `requirement` (with `moscow` classification),
  `adr` (status, date, supersedes, related requirements),
  `policy` (severity, package, `compliesWith` compliance block equivalent to
  `__rego__metadoc__.compliance`), `component`, `test-suite`, `nfr`,
  `system`.
- **Edges** — `references` (ADR → requirement), `implements`
  (policy/component → ADR), `satisfies` (policy/component → requirement),
  `covers` (test-suite → requirement), `supersedes` (ADR → ADR),
  `traces` (NFR → ADR).

## Integrity model

The normalizer separates *structural* integrity from *referential* policy:

- **Duplicate node ids fail the build.**  Uniqueness is mechanical, not a
  review discipline.
- **Dangling references are recorded, not rejected.**  An edge whose target
  id no source defines lands in `integrity.danglingEdges` (e.g. a test
  covering `spec:REQ-2` before that requirement is written into the SRS).
  Which references *must* resolve is policy — enforced by the OPA
  validation gate on top of this contract, not by normalization.

## Regenerating

```bash
python3 scripts/normalize-traceability-metadata.py --selftest  # embedded checks
python3 scripts/normalize-traceability-metadata.py --all       # write the artefact
```

Both stdlib-only and deterministic: the same tree produces a byte-identical
file (sorted nodes and edges, no timestamps).  CI runs the same two commands
and compares against the committed file.

## Decision record

The three contract decisions (normalize legacy sources indefinitely, ID
registry in this repository, contract schema published here rather than in
the grammar repository) are recorded in
[ADR-0019 — Use a Shared Traceability Metadata Contract for All Spec
Sources](../adrs/0019-shared-traceability-metadata-contract.md).
