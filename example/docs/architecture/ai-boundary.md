# AI/LLM Boundary in the Technical Design Specification

The pipeline's core promise is **determinism**: every generated artefact is
re-derived from version-controlled sources on every run, byte-identically,
and CI fails if the committed copy drifts
([ADR-0018](../adrs/0018-spectree-specification-first-ingestion.md),
[ADR-0021](../adrs/0021-tds-composition-manifest-grammar.md)).  At the same
time the repository exposes the Backstage catalog to AI agents over MCP
([ADR-0009](../adrs/0009-backstage-mcp-server.md)), and AI tools routinely
help draft documentation.  This page states explicitly — per
[ADR-0025](../adrs/0025-ai-consumer-not-producer.md) — which parts of the
TDS are deterministically generated, which are human-authored, and under
what guardrails AI assistance may touch content at all.

The rule in one sentence:

> **AI is a consumer of the TDS, never a producer of spec content.**

## Content Class 1 — Deterministically generated (no AI, ever)

These artefacts are machine-produced from code and configuration by
deterministic generators.  They are regenerated on every pipeline run and
drift-gated (`git diff --exit-code`): a hand edit — human *or* AI — is
reverted or fails CI.  No LLM participates in producing them.

| Artefact | Deterministic producer | Gate |
|----------|------------------------|------|
| Terraform module reference | `terraform-docs` | docs-build regenerates |
| Ansible host report | Jinja2 template | docs-build regenerates |
| DSC resource docs | `DscResource.DocGenerator` | docs-build regenerates |
| OPA policy docs | metadoc scan | docs-build regenerates |
| OpenAPI reference | `scripts/generate-openapi-docs.py` ([ADR-0015](../adrs/0015-native-dotnet-openapi.md)) | docs-build regenerates |
| C4 diagrams | C4Sharp ([ADR-0017](../adrs/0017-c4sharp-architecture-diagrams.md)) | docs-build regenerates |
| .NET API reference | DocFX ([ADR-0013](../adrs/0013-docfx-dotnet-api-reference.md)) | docs-build regenerates |
| Filtered .NET API export | `scripts/generate-dotnet-doc-export.py` ([ADR-0022](../adrs/0022-xml-doc-filtered-api-export.md)) | CI-generated, spec ids verified |
| SpecTree ASTs | `scripts/spectree-parse.py` ([ADR-0018](../adrs/0018-spectree-specification-first-ingestion.md)) | kit job selftest + regen |
| Traceability metadata | `scripts/normalize-traceability-metadata.py` ([ADR-0019](../adrs/0019-shared-traceability-metadata-contract.md)) | committed, drift-gated |
| Architecture catalog + drawio | `scan-architecture.py` / `generate-traceability.py` ([ADR-0012](../adrs/0012-machine-readable-adr-traceability.md)) | committed, drift-gated |
| TDS composition report | `scripts/generate-tds-composition.py` ([ADR-0021](../adrs/0021-tds-composition-manifest-grammar.md)) | committed, blob-SHA-bound |
| Network topology | `terraform plan` hook (OPS-003) | pipeline-generated |
| Drift report | `scripts/generate-drift-report.py` ([ADR-0024](../adrs/0024-infrastructure-drift-detection.md)) | incident snapshot, never committed |

Why "never" is structural, not just policy: the drift gate makes an
LLM-authored (or hand-authored) edit to any committed artefact impossible
to keep — the next CI run overwrites it or fails the build.  An LLM has
nothing legitimate to add here.

## Content Class 2 — Human-authored, version-controlled Markdown

These pages are written by people, in pull requests, and carry the
project's reasoning rather than derived facts:

- ADRs (`docs/adrs/`) — decisions, context, trade-offs
- MoSCoW requirements (`docs/requirements/moscow.md`)
- Runbook and operational procedures (`docs/runbook/`)
- Traceability narrative (`docs/traceability/`)
- Architecture, application, security, compliance, FinOps narrative pages
- Governance prose generally

They are gated like code: the [ADR boundary
gate](../adrs/0012-machine-readable-adr-traceability.md) requires every
governed change to cite its ADR, the documentation coverage gate requires
code changes to bring their docs along
([ADR-0006](../adrs/0006-enforce-doc-coverage-gate.md)), and the strict
MkDocs build fails on broken links or missing pages.

## Content Class 3 — AI-assisted, admitted only through Class 2

AI tools **may** help draft Class 2 content — an ADR's prose, a runbook
update, the wording of a requirement.  The guardrails are not special;
they are the same gates every change passes:

1. **A human owns the pull request.**  AI-drafted text is a proposal,
   reviewed and approved like any human draft — never a direct commit.
2. **The output lands as ordinary version-controlled Markdown** (Class 2)
   and passes identical gates: boundary gate ADR citations, doc coverage,
   strict-link build, SpecTree validation where applicable.
3. **AI never writes into `docs/generated/`** (Class 1 territory) and is
   **never a pipeline step**: no CI job calls an LLM, because any
   generated artefact must be byte-reproducible from the tree alone
   ([ADR-0018](../adrs/0018-spectree-specification-first-ingestion.md)).
4. **Grammar, parsers, schemas, and policies** may be *proposed* by AI but
   ship only with their selftests and policy tests green
   (spectree selftests, `opa test policies/`).

## AI as a consumer

The sanctioned AI surface is read-only consumption:

- The [Backstage MCP server](../backstage/mcp.md) (ADR-0009) exposes the
  entity catalog (`list_catalog_entities`, `get_entity_by_name`, …) so
  agents can explore the system without custom integration.
- The published MkDocs site and the committed JSON artefacts (catalog,
  metadata contract, composition report) are stable, versioned inputs an
  agent may read.
- An agent that *proposes* changes still goes through the same PR gates
  as a human — consumption may trigger contribution, but never bypasses
  review.

Extending MCP tooling to serve the traceability metadata would be
read-only consumption and is compatible with this boundary; producing
spec content is not.

## Verifying the boundary

The boundary is enforced by existing gates, not by trust:

- The kit job re-runs every generator and fails on committed drift.
- The boundary gate blocks governed changes that cite no ADR.
- The doc-coverage gate couples code and documentation changes.
- Selftests pin parser and generator behavior.

If a future feature would put an LLM anywhere in the generation path, it
requires superseding [ADR-0025](../adrs/0025-ai-consumer-not-producer.md)
— the decision is deliberately explicit so it cannot erode silently.

---

Satisfies [AI-004](../requirements/moscow.md).  Decision record:
[ADR-0025 — AI as Consumer, Not Producer of TDS
Content](../adrs/0025-ai-consumer-not-producer.md).
