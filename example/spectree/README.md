# SpecTree — specification-first sources for the example pipeline

This directory holds the example **SpecTree**: machine-readable specification
files for the `MyApp` .NET solution under `../dotnet/`, plus pinned copies of
the grammar files that define their syntax.

## Layout

| Path | Contents |
| --- | --- |
| `specs/` | Specification files mirroring the MyApp solution (one per SpecTree format) |
| `grammars/` | Vendored grammar files from [Minotaur-Grammars](https://github.com/DevelApp-ai/Minotaur-Grammars) `specification-first/` |
| `schemas/` | Versioned JSON Schema for the ASTs emitted by the parser |

## Formats and example files

| Grammar | Extension | Example file | What it declares |
| --- | --- | --- | --- |
| SrsSpec | `.srs` | `specs/myapp.srs` | System requirements with MoSCoW priorities and traceability links |
| AiSpec | `.ai` | `specs/todoapi.ai`, `specs/todoservice.ai` | Component metadata, requirements, API surface, ADR compliance |
| TestSpec | `.test` | `specs/todoservice.test` | Scenario-based tests, edge cases, coverage rules, performance thresholds |
| ApiSpec | `.api` | `specs/todoapi.api` | Versioned REST contract: endpoints, schemas, error contracts |
| ModelSpec | `.model` | `specs/todo.model` | Entities, relationships, invariants |
| NsSpec | `.ns` | `specs/myapp.ns` | Measurable non-functional budgets, security and compliance constraints |
| AdrSpec | `.adr` | `specs/spectree-ingestion.adr` | Architectural design record with status lifecycle and requirement links |
| SolutionManifest | `.manifest` | `specs/myapp.manifest` | Binding of the spec tree to the .NET solution |

## Parsing

`scripts/spectree-parse.py` (from the `example/` root) parses every format:

```bash
# parse all specs under spectree/specs/ → docs/generated/spectree/*.ast.json
python3 scripts/spectree-parse.py --all

# parse a single file and print the AST JSON
python3 scripts/spectree-parse.py --spec spectree/specs/myapp.srs

# run the embedded unit tests (also validates the committed specs against the schema)
python3 scripts/spectree-parse.py --selftest
```

ASTs are **generated artefacts**: they are git-ignored under
`docs/generated/spectree/` and rebuilt on every pipeline run. The stable AST
contract is the committed JSON Schema `schemas/spectree-ast-v1.schema.json`
(versioned independently of the grammars).

## Determinism and gates

The parser holds the same bar as the rest of the generated estate
(`docs/generated/`):

- **Byte-deterministic output** — repeated `--all` runs produce identical
  ASTs (verifiable with `md5sum docs/generated/spectree/*.ast.json` across
  runs); no timestamps, no unordered iteration.
- **Schema-gated emission** — every AST is validated against the committed
  schema *before* it is written; an unparseable or unvalidatable spec fails
  the run with a `file:line` diagnostic, never silently.
- **Selftest as a CI gate** — `scripts/generate-docs.sh` (Step 5) runs
  `--selftest` before `--all`, so a broken parser or a broken spec fails the
  docs build:
  ```
  spectree-parse selftest: 120 checks passed, 0 failed
  spectree-parse: 9 AST(s) written to docs/generated/spectree
  ```

## Grammar provenance

The grammar files under `grammars/` are byte-identical copies of
`specification-first/<dir>/<Name>.grammar` in the Minotaur-Grammars repository
at commit `de45cd55169d` — the grammar source of truth for the SpecTree
formats. Re-vendor them deliberately (and bump the pinned commit referenced
here) when the grammar suite changes; the parser is written against these
files.

The decision to ingest the SpecTree as first-class pipeline sources is
recorded in ADR-0018 (`docs/adrs/0018-spectree-specification-first-ingestion.md`).
