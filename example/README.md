# Deterministic Documentation Pipeline — Example

A fully working demonstration of the principles described in
**"Documenting Deterministic Infrastructure Code"**.

Every piece of documentation in the generated site is either:

- **auto-generated** from source code (Terraform HCL, Ansible facts, OPA Rego metadata), or
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

### Option B — Native (requires tools on PATH)

Install the required tools:

| Tool | Version | Install |
|------|---------|---------|
| Terraform | ≥ 1.5 | [developer.hashicorp.com](https://developer.hashicorp.com/terraform/install) |
| terraform-docs | ≥ 0.19 | [terraform-docs.io](https://terraform-docs.io/user-guide/installation/) |
| OPA | ≥ 0.60 | [openpolicyagent.org](https://www.openpolicyagent.org/docs/latest/#running-opa) |
| Ansible | ≥ 10 | `pip install ansible` |
| MkDocs + Material | ≥ 1.5 / 9 | `pip install mkdocs mkdocs-material pymdown-extensions` |

Then run:

```bash
cd example
bash scripts/generate-docs.sh
```

---

## CI/CD Pipeline

The GitHub Actions workflow at `.github/workflows/docs-pipeline.yml` runs
automatically on every push to `main` or pull request touching `example/`.

```
Pull Request
     │
     ▼
┌─────────────┐    ┌──────────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  OPA Tests  │───▶│  Terraform + OPA     │───▶│  Docs Build      │───▶│  GitHub Pages   │
│  (opa test) │    │  Validate, Plan,     │    │  terraform-docs  │    │  Deploy         │
│             │    │  OPA gate            │    │  Ansible         │    │  (main only)    │
└─────────────┘    └──────────────────────┘    │  MkDocs build    │    └─────────────────┘
                                               └──────────────────┘
```

A pull request that introduces an OPA policy violation (e.g., a resource missing
a required FinOps tag) **cannot be merged** — the pipeline fails and the denial
messages are surfaced as job output.

---

## Directory Structure

```
example/
├── Dockerfile                           # Multi-stage toolchain image
├── Dockerfile.backstage                 # Standalone Backstage developer portal
├── README.md                            # This file
├── catalog-info.yaml                    # Backstage entity descriptor
├── mkdocs.yml                           # MkDocs site configuration
├── .github/
│   └── workflows/
│       └── docs-pipeline.yml            # GitHub Actions pipeline
├── backstage/
│   └── app-config.yaml                  # Backstage application configuration
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
│   └── terraform/
│       ├── deny_missing_tags.rego       # FINOPS-001 (with related_adr, related_requirements)
│       ├── deny_missing_tags_test.rego  # Unit tests for FINOPS-001
│       └── deny_unencrypted_storage.rego# SEC-001 (with related_adr, related_requirements)
├── docs/
│   ├── index.md                         # Site home page
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
│       └── terraform-readme.md          # terraform-docs output (seeded copy)
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

### Adding a new ADR

1. Copy an existing ADR from `docs/adrs/` as a template.
2. Increment the ADR number and update the front-matter metadata.
3. Add the new file to the `nav` section of `mkdocs.yml`.

### Switching to real cloud infrastructure

1. Replace the `local` provider resources in `terraform/main.tf` with real
   AWS / Azure / GCP resources.
2. Add provider credentials as GitHub Actions secrets.
3. The OPA policies and terraform-docs integration continue to work without
   any changes.
