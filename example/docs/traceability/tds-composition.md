# TDS Composition Manifest

Since [ADR-0021](../adrs/0021-tds-composition-manifest-grammar.md), the
assembled Technical Design Specification is declared **as data**: a
SpecTree line-grammar manifest states which sources compose into which
TDS, in which order, under which inclusion/exclusion rules, and for
which rendering targets. This page documents the grammar, the manifest
for the MyApp solution, and the deterministic composition report.

## The manifest

The reference manifest is
[`spectree/tds/myapp.tds`](https://github.com/DevelApp-ai/deterministic-technical-design-specification/blob/main/example/spectree/tds/myapp.tds),
bound to the SolutionManifest
([ADR-0018](../adrs/0018-spectree-specification-first-ingestion.md)) of
the same solution:

```text
# TDS: MyApp Technical Design Specification
## Solution: myapp.manifest
## Version: 1.0.0

## Target: mkdocs (nav: Traceability)
## Target: techdocs (publisher: docs)
## Target: standalone (path: docs/generated/tds)

### Section: Requirements
- Source: docs/requirements/*.md
- Rule: summarize wont requirements

### Section: Architecture Decisions
- Source: docs/adrs/*.md
- Rule: appendix superseded adrs
- Selector: docs/generated/traceability/metadata-v1.json#adr
```

*(excerpt — the committed manifest declares all twelve sections of the
published site)*

### Grammar rules

| Line | Cardinality | Meaning |
|------|-------------|---------|
| `# TDS: <title>` | exactly one | Document title |
| `## Solution: <name>` | exactly one | Bound SolutionManifest; `spectree/specs/<name>` must exist |
| `## Version: <semver>` | exactly one | Semantic version of the composed TDS |
| `## Target: <kind> (k: v, …)` | at least one | Rendering target — `mkdocs` (`nav:`), `techdocs` (`publisher:`), `standalone` (`path:`, must be under `docs/generated/`) |
| `### Section: <title>` | at least one, ordered, unique | Document section, in reading order |
| `- Source: <glob>` | at least one per section | Files (pipeline-root-relative glob) composing the section; must match at least one file |
| `- Source: <glob> (generated)` | — | Pipeline-generated artefact: declared but never blob-bound |
| `- Selector: <artefact>#<node-type>` | optional | AST node selector over a generated JSON artefact; resolved with node counts |
| `- Rule: <phrase>` | optional | Inclusion/exclusion rule from the fixed vocabulary |

The parsed shape is published as
[`spectree/schemas/tds-manifest-v1.schema.json`](https://github.com/DevelApp-ai/deterministic-technical-design-specification/blob/main/example/spectree/schemas/tds-manifest-v1.schema.json).

### Rule vocabulary

| Rule | Semantics |
|------|-----------|
| `summarize wont requirements` | Won't-classified MoSCoW items appear as summary rows only, not as detailed requirements |
| `appendix superseded adrs` | Superseded ADRs are listed in an appendix, not detailed in the decision section |
| `exclude deprecated adrs` | Deprecated ADRs are excluded from the composed decision record |
| `detail public api` | The application section details the public API surface (visibility-filtered) |
| `exclude test projects` | Test projects are excluded from API documentation |

## The composition report

`scripts/generate-tds-composition.py --all` resolves every manifest
against the tree and emits a **committed, drift-gated** report:
[`myapp.composition.json`](../generated/tds/myapp.composition.json).
For every composed source file it records the **git blob SHA** —
computed in pure Python, byte-identical to `git hash-object` — so a
rebuild from the same tree provably assembles the same document. The
report also carries resolved selector counts and section totals.

Artefacts marked `(generated)` — the
[DocFX API reference](../generated/dotnet-api/MyApp.Domain.md) and the
[OpenAPI document](../generated/openapi.json) — are declared but not
blob-bound: they do not exist in a fresh checkout, and their content
integrity derives from the deterministic build that produces them from
blob-bound sources ([ADR-0013](../adrs/0013-docfx-dotnet-api-reference.md),
[ADR-0015](../adrs/0015-native-dotnet-openapi.md)).

## Targets

- **MkDocs** — the generator verifies the declared nav anchor exists in
  `mkdocs.yml` ([ADR-0003](../adrs/0003-use-mkdocs-for-publishing.md));
  publishing configuration stays in `mkdocs.yml`.
- **Backstage TechDocs** — the manifest declares the publisher; the
  integration lives in [`catalog-info.yaml`](../backstage/index.md).
- **Standalone export** — the composition report itself is the
  machine-readable standalone export under `docs/generated/tds/`.

## Filtered .NET API export

[ADR-0022](../adrs/0022-xml-doc-filtered-api-export.md) implements the
manifest's `detail public api` / `exclude test projects` rules for the
application layer: `scripts/generate-dotnet-doc-export.py` renders the
public API surface of each application assembly from the build-time XML
doc comments into
`docs/generated/tds/dotnet-api/` (CI-generated, declared
`(generated)` in the manifest), plus the machine-readable
code→spec mapping `docs/generated/tds/dotnet-spec-mapping.json`.
Members declare their requirement traces with `<spec>` tags —
every id is verified against this metadata contract, so application
code and specification cannot drift apart silently.

## Regenerating

```bash
python3 scripts/generate-tds-composition.py --selftest   # 38 checks
python3 scripts/generate-tds-composition.py --all        # writes docs/generated/tds/
```

CI runs both in the traceability kit job and the docs build, and fails
if the committed report differs from the regenerated one — the same
drift bar the [architecture catalog](index.md) and
[metadata contract](metadata-contract.md) hold.
