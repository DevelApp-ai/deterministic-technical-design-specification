# Deterministic Documentation Pipeline — Example

A fully working demonstration of the principles described in
**"Documenting Deterministic Infrastructure Code"**.

Every piece of documentation in the generated site is either:

- **auto-generated** from source code (Terraform HCL, Ansible facts, OPA Rego
  metadata, .NET assemblies), or
- **version-controlled Markdown** co-located with the code it describes (ADRs, MoSCoW requirements).

Nothing is written manually after the fact.

---

## Concepts Demonstrated

| Concept | Tool | Location |
|---------|------|----------|
| Infrastructure as Code | Terraform (`local` provider) | `terraform/` |
| FinOps as Code | Cost-allocation tags enforced by OPA | `policies/terraform/deny_missing_tags.rego` |
| Policy as Code | OPA + Rego with self-describing `__rego__metadoc__` | `policies/terraform/` |
| Policy Unit Tests | `opa test` | `policies/terraform/*_test.rego` |
| Auto-generated IaC docs | terraform-docs | `docs/generated/terraform-readme.md` |
| Living configuration docs | Ansible + Jinja2 | `ansible/templates/host-report.md.j2` |
| PowerShell DSC | Class-based DSC resource + Pester tests + DscResource.DocGenerator | `dsc/` |
| Application as Code | ASP.NET Core API (layered: Api → Application → Domain) | `dotnet/src/` |
| .NET API docs | DocFX (Markdown export) | `docs/generated/dotnet-api/` |
| Architecture policy | NetArchTest + xUnit | `dotnet/tests/MyApp.ArchitectureTests/` |
| Code quality gate | Roslyn analyzers (NetAnalyzers, Roslynator, SonarAnalyzer) + `TreatWarningsAsErrors` | `dotnet/Directory.Build.props`, `dotnet/.editorconfig` |
| API contract docs | .NET native OpenAPI (build-time, no Swashbuckle) | `docs/generated/openapi.json` |
| App architecture diagrams | C4Sharp → Mermaid | `docs/generated/architecture/` |
| MoSCoW requirements | Machine-readable Markdown | `docs/requirements/moscow.md` |
| Architectural Decision Records | Structured Markdown with front-matter | `docs/adrs/` |
| Traceability | OPA policy → ADR → MoSCoW requirement with Mermaid diagrams | `docs/traceability/index.md` |
| Documentation publishing | MkDocs + Material theme | `mkdocs.yml` |
| Developer portal | Backstage TechDocs integration | `catalog-info.yaml`, `Dockerfile.backstage` |
| CI/CD pipeline | GitHub Actions | `.github/workflows/docs-pipeline.yml` |

---

## Quick Start

### Option A — Docker (recommended, no host dependencies)

```bash
# Build the toolchain image
docker build -t dtds-example example/

# Verify all tools are installed
docker run --rm dtds-example

# Run the full documentation pipeline
docker run --rm \
  -v "$(pwd)/example":/workspace \
  dtds-example \
  bash scripts/generate-docs.sh

# Serve the generated site locally
docker run --rm -p 8000:8000 \
  -v "$(pwd)/example":/workspace \
  dtds-example \
  mkdocs serve --dev-addr 0.0.0.0:8000 -f mkdocs.yml
```

Then open [http://localhost:8000](http://localhost:8000).

### Option B — Backstage Developer Portal

Build and run the standalone Backstage image to get a full developer portal
with TechDocs integration:

```bash
# Build (takes ~8-12 minutes — downloads Node.js dependencies)
docker build -f example/Dockerfile.backstage -t dtds-backstage example/

# Run the portal
docker run --rm -p 7007:7007 dtds-backstage
```

Then open [http://localhost:7007](http://localhost:7007).  The portal shows:
- **Catalog** → `deterministic-docs-example` component
- **Docs** tab → TechDocs site with all ADRs, requirements, traceability and compliance pages

### Option C — Native (requires tools on PATH)

Install the required tools:

| Tool | Version | Install |
|------|---------|---------|
| Terraform | ≥ 1.5 | [developer.hashicorp.com](https://developer.hashicorp.com/terraform/install) |
| terraform-docs | ≥ 0.19 | [terraform-docs.io](https://terraform-docs.io/user-guide/installation/) |
| OPA | ≥ 0.60 | [openpolicyagent.org](https://www.openpolicyagent.org/docs/latest/#running-opa) |
| Ansible | ≥ 10 | `pip install ansible` |
| MkDocs + Material | ≥ 1.5 / 9 | `pip install mkdocs mkdocs-material pymdown-extensions` |
| .NET SDK | 10.0.404 (pinned) | [dot.net](https://dotnet.microsoft.com/download) — see `dotnet/global.json` |

Then run:

```bash
cd example
bash scripts/generate-docs.sh
```

### Application workload (.NET)

The .NET application layer has its own build and test gates:

```bash
cd example/dotnet
dotnet tool restore                    # restores the pinned DocFX tool
dotnet build MyApp.slnx -c Release    # Roslyn code-quality gate + native OpenAPI export
dotnet test MyApp.slnx --no-build     # unit tests + NetArchTest architecture policies
```

`scripts/generate-docs.sh` runs these steps automatically (Step 5) when
`dotnet` is on the PATH and skips them with a warning otherwise. The Docker
toolchain image ships the pinned .NET SDK and DocFX, so the same steps run
inside the container with no host dependencies.

---

## CI/CD Pipeline

The GitHub Actions workflow at `.github/workflows/docs-pipeline.yml` runs
automatically on every push to `main` or pull request touching `example/`.

```
Pull Request
     │
     ▼
┌──────────────┐   ┌─────────────┐   ┌──────────────────────┐   ┌──────────────────┐   ┌─────────────────┐
│ .NET Build + │──▶│  OPA Tests  │──▶│  Terraform + OPA     │──▶│  Docs Build      │──▶│  GitHub Pages   │
│ Tests        │   │  (opa test) │    │  Validate, Plan,     │    │  terraform-docs  │    │  Deploy         │
│ Roslyn gate, │   │             │    │  OPA gate            │    │  Ansible        │    │  (main only)    │
│ NetArchTest  │   │             │    │                      │    │  .NET API docs  │    │                 │
└──────────────┘   └─────────────┘    └──────────────────────┘    │  + MkDocs build │    └─────────────────┘
                                                                └──────────────────┘
```

A pull request that introduces a Roslyn analyzer violation, a NetArchTest
architecture-policy violation, or an OPA policy violation (e.g., a resource
missing a required FinOps tag) **cannot be merged** — the pipeline fails and
the findings are surfaced as job output.

The .NET stage (`dotnet build` + `dotnet test`) also regenerates the
application-layer documentation: the DocFX API reference, the native OpenAPI
document, and the C4Sharp diagrams.

---

## ADR Traceability Kit (ADR-0012)

The repository's architecture decisions are machine-readable, traversable, and
enforced at PR time:

| Piece | Where | What it does |
|-------|-------|--------------|
| Catalog scanner | `scripts/scan-architecture.py` | Extracts ADR front-matter, policy metadocs, and MoSCoW requirement ids into `docs/generated/architecture-catalog.json` (deterministic, stdlib-only) |
| Catalog validation | `policies/architecture/validate.rego` | 14 loud findings over the catalog — duplicate ids, cyclic/dangling supersedes, status/chain mismatches, ADRs without requirements or `governs` territory, policy metadoc defects |
| Chain traversal | `policies/architecture/chain.rego` | `effective[id]` resolves the current ADR of any supersede chain (bounded 8-hop closure — Rego forbids recursion; the cap is loud, never silent) |
| PR boundary gate | `policies/architecture/gate.rego` + `scripts/architecture-gate.sh` | Fails a PR that changes a governed path without citing the governing ADR (`ADR-####` in the PR description); redirects superseded links to the successor |
| Diagram generator | `scripts/generate-traceability.py` | Regenerates `docs/generated/traceability.drawio` (book diagram conventions) byte-identically; CI fails if the committed diagram drifts |
| End-to-end demo | `scripts/architecture-demo.sh` | Proves the done-when scenario with inverted expectations: blocked without a linked ADR, passes with one, superseded link redirected, diagram regen `cmp`-identical |

Every ADR's front-matter declares a `governs:` list of the paths it protects —
a change to any of them requires the ADR to be cited in the PR description.
The `architecture` CI job runs the kit on every push and PR.

---

## Directory Structure

```
example/
├── Dockerfile                           # Multi-stage toolchain image
├── Dockerfile.backstage                 # Standalone Backstage developer portal
├── README.md                            # This file
├── catalog-info.yaml                    # Backstage entity descriptor
├── mkdocs.yml                           # MkDocs site configuration
├── backstage/
│   └── app-config.yaml                  # Backstage application configuration
│                                         # (CI workflow: .github/workflows/docs-pipeline.yml at the repo root —
│                                         # GitHub Actions only reads workflows from <repo-root>/.github/workflows/)
├── dotnet/                              # .NET application workload (ADR-0013 – ADR-0017)
│   ├── MyApp.slnx                       # Solution (.NET 10 solution file format)
│   ├── global.json                      # Pinned .NET SDK version (10.0.404)
│   ├── Directory.Build.props            # Analyzers, deterministic build, warnings-as-errors
│   ├── .editorconfig                    # Roslyn analyzer severities (code-quality gate)
│   ├── dotnet-tools.json                # Pinned local tools (DocFX)
│   ├── src/
│   │   ├── MyApp.Api/                   # Controllers, DTOs, build-time OpenAPI export
│   │   ├── MyApp.Application/           # Application services + repository contracts
│   │   └── MyApp.Domain/                # Domain entities (pure model)
│   ├── tests/
│   │   ├── MyApp.UnitTests/             # xUnit unit tests
│   │   └── MyApp.ArchitectureTests/     # NetArchTest architecture policies (APP-ARCH-*, APP-SEC-*)
│   ├── tools/
│   │   └── MyApp.Architecture.Diagrams/ # C4Sharp → Mermaid C4 diagram generator
│   └── docs/
│       └── docfx.json                   # DocFX configuration (Markdown export)
├── terraform/
│   ├── main.tf                          # Infrastructure resources (local provider)
│   ├── variables.tf                     # Input variables (parsed by terraform-docs)
│   ├── outputs.tf                       # Output values   (parsed by terraform-docs)
│   └── terraform.tfvars.example         # Example variable values
├── ansible/
│   ├── playbook.yml                     # Fact-gathering playbook
│   ├── inventory.yml                    # Static inventory (localhost)
│   └── templates/
│       └── host-report.md.j2            # Jinja2 → deterministic Markdown
├── policies/
│   ├── terraform/
│   │   ├── deny_missing_tags.rego       # FINOPS-001 (with related_adr, related_requirements)
│   │   ├── deny_missing_tags_test.rego  # Unit tests for FINOPS-001
│   │   └── deny_unencrypted_storage.rego# SEC-001 (with related_adr, related_requirements)
│   └── architecture/                    # ADR-0012 traceability kit (validate, chain, gate)
├── docs/
│   ├── index.md                         # Site home page
│   ├── application/                     # Application layer chapter (overview, quality gate,
│   │                                    # architecture policies, diagrams, API reference)
│   ├── adrs/                            # ADRs (related_requirements in front-matter)
│   │   ├── 0001-use-terraform-for-iac.md
│   │   ├── 0002-use-opa-for-policy.md
│   │   └── 0003-use-mkdocs-for-publishing.md
│   ├── requirements/
│   │   └── moscow.md                    # MoSCoW requirements
│   ├── traceability/
│   │   └── index.md                     # Mermaid diagrams: MoSCoW → ADR → Policy
│   ├── backstage/
│   │   └── index.md                     # Backstage integration guide
│   ├── infrastructure/
│   │   └── terraform.md                 # Terraform module docs page
│   ├── configuration/
│   │   └── ansible.md                   # Ansible host report page
│   ├── compliance/
│   │   └── opa-policies.md              # OPA policy summary with traceability links
│   └── generated/                       # Auto-generated artefacts (git-ignored)
│       ├── terraform-readme.md          # terraform-docs output (seeded copy)
│       ├── dotnet-api/                  # DocFX Markdown export (build-time)
│       ├── openapi.json                 # Native build-time OpenAPI document
│       └── architecture/                # C4Sharp Mermaid + PlantUML sources (build-time)
└── scripts/
    └── generate-docs.sh                 # Local one-shot pipeline runner
```

---

## Extending the Example

### Adding a new OPA policy

1. Create `policies/terraform/deny_<name>.rego` with a `deny` rule set and a
   `__rego__metadoc__` block.
2. Create `policies/terraform/deny_<name>_test.rego` with `opa test`-compatible
   unit tests.
3. Add a corresponding row to `docs/compliance/opa-policies.md`.
4. The CI pipeline will automatically evaluate the new policy on the next push.

### Adding a new .NET architecture policy

1. Add the policy to
   `dotnet/tests/MyApp.ArchitectureTests/ArchitecturePoliciesTests.cs` — either
   a `Policy.Define("APP-XXX-000", "description")` NetArchTest policy or a
   custom test with a matching `("APP-XXX-000", "description")` metadata tuple.
2. Reference the requirement id it enforces in `docs/requirements/moscow.md`
   (APP-xxx) and, where applicable, in the ADR's `related_requirements`
   front-matter.
3. Regenerate the policy page:
   `python3 scripts/generate-dotnet-policy-docs.py`.
4. Regenerate the traceability artifacts:
   `python3 scripts/scan-architecture.py && python3 scripts/generate-traceability.py`.

### Adding a new ADR

1. Copy an existing ADR from `docs/adrs/` as a template.
2. Increment the ADR number and update the front-matter metadata, including
   `governs:` — the paths the decision protects (required for Accepted ADRs;
   `validate.rego` flags one without territory). Note the numbering landscape:
   ADR-0001 – ADR-0012 cover the infrastructure estate and the traceability
   kit; the .NET application series runs ADR-0013 – ADR-0017, so new
   application-layer decisions start at ADR-0018.
3. Add the new file to the `nav` section of `mkdocs.yml`.
4. Regenerate the artifacts and commit them:
   `python3 scripts/scan-architecture.py && python3 scripts/generate-traceability.py`
5. A PR touching a path in `governs:` must cite the ADR id (`ADR-####`) in
   its description or the boundary gate fails it.

### Switching to real cloud infrastructure

1. Replace the `local` provider resources in `terraform/main.tf` with real
   AWS / Azure / GCP resources.
2. Add provider credentials as GitHub Actions secrets.
3. The OPA policies and terraform-docs integration continue to work without
   any changes.
