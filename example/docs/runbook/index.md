# Operational Runbook

This runbook covers the **day-2 operational procedures** for the deterministic
documentation platform.  It is the DevOps team's first reference for incidents,
deployments, and routine maintenance.

!!! tip "Principle"
    Every procedure in this runbook is executable from the Docker toolchain
    image — no host tool installation required.

---

## Quick Reference

| Action | Command |
|--------|---------|
| Run full doc pipeline locally | `docker run --rm -v "$(pwd)":/workspace dtds-example scripts/generate-docs.sh` |
| Serve docs locally | `docker run --rm -p 8000:8000 -v "$(pwd)":/workspace dtds-example mkdocs serve -f example/mkdocs.yml --dev-addr 0.0.0.0:8000` |
| Run OPA policy tests | `docker run --rm -v "$(pwd)":/workspace dtds-example opa test example/policies/terraform/ -v` |
| Run Pester DSC tests | `docker run --rm -v "$(pwd)":/workspace dtds-example pwsh -Command "Invoke-Pester example/dsc/tests/ -Output Detailed"` |
| Validate Terraform | `docker run --rm -v "$(pwd)":/workspace dtds-example bash -c "cd example/terraform && terraform init && terraform validate"` |
| Generate DSC docs | `docker run --rm -v "$(pwd)":/workspace dtds-example pwsh -File example/dsc/build.ps1` |

---

## CI/CD Pipeline Operations

### Re-triggering a Failed Pipeline

```bash
# Manually trigger the workflow (requires gh CLI)
gh workflow run docs-pipeline.yml --ref main

# Or push an empty commit to re-trigger on push
git commit --allow-empty -m "chore: re-trigger pipeline"
git push
```

### Viewing Pipeline Logs

```bash
# List recent workflow runs
gh run list --workflow docs-pipeline.yml --limit 10

# View logs for a specific run
gh run view <RUN_ID> --log
```

---

## Incident Response

The following flowchart covers the most common failure scenarios.

```mermaid
flowchart TD
    START([🚨 Alert: Pipeline Failed]) --> IDENTIFY{Which job failed?}

    IDENTIFY -->|opa-tests| OPA_FAIL[OPA unit test failure]
    IDENTIFY -->|dsc-tests| DSC_FAIL[Pester test failure]
    IDENTIFY -->|terraform| TF_FAIL[Terraform or OPA gate failure]
    IDENTIFY -->|docs-build| DOCS_FAIL[Documentation build failure]
    IDENTIFY -->|docs-publish| PUB_FAIL[GitHub Pages deploy failure]

    OPA_FAIL --> OPA_STEPS["1. Run: opa test policies/terraform/ -v\n2. Identify failing test\n3. Fix policy or test\n4. Push fix"]

    DSC_FAIL --> DSC_STEPS["1. Run: Invoke-Pester dsc/tests/ -Output Detailed\n2. Identify failing test\n3. Check DTDS_FileContent.psm1\n4. Push fix"]

    TF_FAIL --> TF_TYPE{Error type?}
    TF_TYPE -->|validate error| TF_SYNTAX["Fix HCL syntax in terraform/\nRun: terraform validate"]
    TF_TYPE -->|OPA deny| TF_POLICY["Policy violated:\n1. Read denial message\n2. Fix the resource in terraform/\n   OR\n3. Update OPA policy if rule is wrong\n4. Run: opa test policies/ -v first"]
    TF_TYPE -->|plan error| TF_PROVIDER["Provider or dependency error:\n1. Check terraform init output\n2. Check provider versions in main.tf\n3. Run: terraform init -upgrade"]

    DOCS_FAIL --> DOCS_TYPE{Error type?}
    DOCS_TYPE -->|mkdocs build| MKDOCS_ERR["1. Run: mkdocs build --config-file example/mkdocs.yml --strict\n2. Check for broken links or missing files\n3. Fix referenced pages in mkdocs.yml nav"]
    DOCS_TYPE -->|terraform-docs| TFDOCS_ERR["1. Check terraform-docs version\n2. Confirm output-file path exists\n3. Run: terraform-docs markdown table example/terraform/"]
    DOCS_TYPE -->|ansible| ANSIBLE_ERR["1. Check inventory.yml is valid\n2. Run: ansible-playbook -i ansible/inventory.yml ansible/playbook.yml --check"]

    PUB_FAIL --> PUB_STEPS["1. Check GitHub Pages is enabled\n   (repo Settings → Pages → Source: GitHub Actions)\n2. Check GITHUB_TOKEN permissions\n   (repo Settings → Actions → Workflow permissions: Read and write)\n3. Re-run the docs-publish job only"]

    OPA_STEPS --> RESOLVED([✅ Resolved])
    DSC_STEPS --> RESOLVED
    TF_SYNTAX --> RESOLVED
    TF_POLICY --> RESOLVED
    TF_PROVIDER --> RESOLVED
    MKDOCS_ERR --> RESOLVED
    TFDOCS_ERR --> RESOLVED
    ANSIBLE_ERR --> RESOLVED
    PUB_STEPS --> RESOLVED
```

---

## Routine Maintenance Procedures

### Updating Tool Versions

All tool versions are pinned in the `Dockerfile`.  To upgrade:

1. Update the `ARG` value in `example/Dockerfile`
2. Build and test locally: `docker build -t dtds-example example/`
3. Run the smoke test: `docker run --rm dtds-example` (prints tool versions)
4. Run the full pipeline: `docker run --rm -v "$(pwd)":/workspace dtds-example scripts/generate-docs.sh`
5. Update the version references in `docs/architecture/index.md` (technology radar)
6. Open a PR with `chore: bump <tool> to <version>`

### Adding a New OPA Policy

1. Create `policies/terraform/deny_<name>.rego` using `import rego.v1`
2. Set `__rego__metadoc__` with `related_adr`, `related_requirements`, and `compliance` fields
3. Create `policies/terraform/deny_<name>_test.rego` with 100% rule coverage
4. Run `opa test policies/terraform/ -v` — all tests must pass
5. Add the policy to `docs/compliance/opa-policies.md`
6. Add the policy to the security controls matrix in `docs/security/index.md`
7. Update `docs/requirements/moscow.md` if a new requirement is being implemented
8. Update `docs/traceability/index.md` diagrams

### Adding a New DSC Resource

1. Create `dsc/resources/<Name>/<Name>.psm1` with class-based DSC resource
2. Create `dsc/resources/<Name>/<Name>.psd1` module manifest
3. Add Pester 5 tests in `dsc/tests/<Name>.Tests.ps1` using `InModuleScope`
4. Run `pwsh -Command "Invoke-Pester dsc/tests/ -Output Detailed"` — all tests must pass
5. `dsc/build.ps1` will auto-generate the documentation page on next CI run
6. Add a nav entry in `mkdocs.yml` if the resource needs a dedicated page

### Adding a New ADR

1. Create `docs/adrs/<number>-<slug>.md` with YAML front-matter including:
   - `id`, `title`, `status`, `date`, `related_requirements`
2. Update `mkdocs.yml` nav — Architecture Decisions section
3. Update `docs/traceability/index.md` — add the ADR to the matrix tables

---

## Health Check Checklist

Run this checklist before any production deployment:

- [ ] `opa test example/policies/terraform/ -v` — all policy tests pass
- [ ] `pwsh -Command "Invoke-Pester example/dsc/tests/ -Output Detailed"` — all DSC tests pass
- [ ] `terraform -chdir=example/terraform validate` — no validation errors
- [ ] `mkdocs build --config-file example/mkdocs.yml --strict` — no warnings or errors
- [ ] `docker build -t dtds-example example/` — image builds cleanly
- [ ] GitHub Actions pipeline shows green on `main` branch

---

## Escalation Matrix

| Severity | Symptom | Owner | SLA |
|----------|---------|-------|-----|
| P1 | OPA gate blocking all PRs | DevOps Lead | 1 hour |
| P1 | GitHub Pages site unavailable | DevOps Lead | 1 hour |
| P2 | Policy false positive blocking valid PR | Security Engineer | 4 hours |
| P2 | Pester tests failing on main | DevOps Engineer | 4 hours |
| P3 | Documentation stale (>24h) | DevOps Engineer | 24 hours |
| P4 | Tool version outdated | Any engineer | Next sprint |
