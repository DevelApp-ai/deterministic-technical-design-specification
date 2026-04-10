# Deterministic Technical Design Specification — Example

!!! info "What is this?"
    This repository is a **working demonstration** of the principles described in
    *"Documenting Deterministic Infrastructure Code"*.  Every page in this site
    is either **auto-generated** from source code or **version-controlled
    Markdown** — nothing is written manually after the fact.

---

## Core Principles

| Principle | Implementation |
|-----------|---------------|
| **Infrastructure as Code** | Terraform (`local` provider — no cloud credentials needed) |
| **Policy as Code** | OPA + Rego policies with `__rego__metadoc__` self-documentation |
| **Documentation as Code** | terraform-docs, Ansible Jinja2 templates, DscResource.DocGenerator, MkDocs Material |
| **MoSCoW Requirements** | Machine-readable Markdown in `docs/requirements/` |
| **ADRs** | Structured Markdown in `docs/adrs/` with front-matter metadata |
| **Traceability** | Full chain: MoSCoW → ADR → OPA policy with Mermaid diagrams |
| **PowerShell DSC** | Class-based DSC resources + Pester tests + DscResource.DocGenerator |
| **Backstage** | `catalog-info.yaml` + `Dockerfile.backstage` for developer portal |
| **CI/CD Pipeline** | GitHub Actions — OPA gate → Pester → terraform-docs → Ansible → MkDocs |

---

## Pipeline Overview

```mermaid
flowchart LR
    A[Pull Request] --> B[terraform validate]
    B --> C[terraform plan -json]
    C --> D{OPA policy gate}
    D -->|deny rules empty| E[terraform-docs]
    D -->|deny rules non-empty| F[❌ Block merge]
    E --> G[Ansible fact-gather]
    G --> H[MkDocs build]
    H --> I[GitHub Pages deploy]
```

---

## Quick Start

```bash
# Build the toolchain Docker image
docker build -t dtds-example .

# Run the full documentation generation pipeline
docker run --rm -v "$(pwd)":/workspace dtds-example scripts/generate-docs.sh

# Serve the docs locally
docker run --rm -p 8000:8000 -v "$(pwd)":/workspace dtds-example \
  mkdocs serve --dev-addr 0.0.0.0:8000 -f example/mkdocs.yml
```

---

## Repository Structure

```
example/
├── Dockerfile                   # Toolchain image (Terraform, OPA, MkDocs, Ansible)
├── Dockerfile.backstage         # Standalone Backstage developer portal image
├── catalog-info.yaml            # Backstage entity descriptor (TechDocs-ref)
├── mkdocs.yml                   # MkDocs site configuration
├── terraform/                   # Example IaC module
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
├── ansible/                     # Configuration management
│   ├── playbook.yml
│   ├── inventory.yml
│   └── templates/
│       └── host-report.md.j2   # Jinja2 → deterministic Markdown
├── policies/terraform/          # OPA/Rego compliance policies
│   ├── deny_missing_tags.rego  # FINOPS-001 (related_adr, related_requirements)
│   ├── deny_missing_tags_test.rego
│   └── deny_unencrypted_storage.rego  # SEC-001
├── backstage/
│   └── app-config.yaml         # Backstage application configuration
├── docs/
│   ├── adrs/                    # ADRs (related_requirements in front-matter)
│   ├── requirements/            # MoSCoW requirements
│   ├── traceability/            # Mermaid diagrams: MoSCoW → ADR → Policy
│   ├── backstage/               # Backstage integration guide
│   ├── infrastructure/          # Terraform documentation pages
│   ├── configuration/           # Ansible documentation pages
│   ├── compliance/              # OPA compliance summary
│   └── generated/               # Auto-generated artefacts (git-ignored)
└── scripts/
    └── generate-docs.sh         # One-shot local doc generation
```
