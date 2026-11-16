# deterministic-technical-design-specification

**Deterministic Technical Design Specification (TDS) system** — a working
pipeline that regenerates a technical design specification's documentation
directly from infrastructure and application source code, so the docs cannot
silently drift from reality.

## What it is

Documentation-as-code, end to end. Every layer of the system — infrastructure,
policy, and application code — carries machine-readable metadata, and every
published page is either auto-generated from that code or version-controlled
beside it. Nothing is written manually after the fact.

## What it covers

| Layer | Stack |
|-------|-------|
| **Infrastructure** | Terraform (IaC), OPA/Rego (policy-as-code with unit tests), Ansible (configuration facts), PowerShell DSC (Windows configuration), Kubernetes + Helm |
| **Application** | ASP.NET Core (layered solution), Roslyn analyzers (code-quality gate), NetArchTest (architecture policies), native build-time OpenAPI, DocFX (API reference), C4Sharp (C4 diagrams from code) |
| **Governance** | ADRs with machine-readable front-matter, MoSCoW requirements, a generated traceability catalog + diagram, and a PR boundary gate that fails changes to governed paths that don't cite the governing ADR |

## The example

The full working demonstration lives in [`example/`](example/README.md) — a
single pipeline that validates the infrastructure, enforces the policies,
builds and tests the .NET application, and assembles a MkDocs site in which
every page is traceable back to a requirement, a decision, and the code that
satisfies them:

- Pipeline overview & quick start: [`example/README.md`](example/README.md)
- Example application layer: [`example/dotnet/README.md`](example/dotnet/README.md)
- Requirements → ADR → policy traceability: [`example/docs/traceability/index.md`](example/docs/traceability/index.md)
