---
id: ADR-0024
title: Infrastructure Drift Detection
status: Accepted
date: 2026-11-16
author: platform-team
tags: [drift, terraform, operations, ci, determinism, scheduled-pipeline]
supersedes: []
related_requirements: [OPS-004]
governs: [scripts/generate-drift-report.py]
---

# ADR-0024 — Infrastructure Drift Detection

## Status

Accepted

## Context

Issue #3 asks the pipeline to detect drift between the deployed
infrastructure state and the configuration in version control, and to fail
loudly with a human-readable diff when the two diverge.  Four questions
shaped the design:

1. **Detection mechanism** — a dedicated drift tool (driftctl,
   terraform-compliance, a cloud inventory) or `terraform plan
   -detailed-exitcode` itself?
2. **When does the check run** — on every push/PR, or on a schedule?
   Drift is a property of the *deployed* world, not of a commit: a pull
   request cannot create or resolve it.
3. **What happens to the report** — committed into `docs/generated/`
   (like the catalog, drawio, and composition artefacts) or published
   another way?
4. **What does "deployed state" mean for this repository today?**  The
   example infrastructure deliberately uses the `local` provider
   (`terraform/main.tf`: "showcase deterministic documentation generation
   without requiring real cloud credentials") and configures **no remote
   state backend** — there is no deployed state to compare against until
   one exists (the gap issue #2 tracks).

## Decision

1. **[DECISION] Detection uses `terraform plan -detailed-exitcode` against
   the remote backend — no third-party drift tool.**  The plan engine is
   already the authority on what "deployed" means (refresh compares state
   to real resources, plan compares state to configuration), it is
   version-pinned in the pipeline (`TERRAFORM_VERSION`), and its exit
   code is the contract: `0` = in sync, `1` = error, `2` = changes
   present, i.e. drift to reconcile.  driftctl and friends add a second
   inventory of the cloud to keep in sync with the first — a new
   non-determinism surface, against the ADR-0018 bar.

2. **[DECISION] The check runs on a nightly schedule and on manual
   dispatch — never on push or pull request.**  A new `drift-check` job
   (job 11 in `docs-pipeline.yml`) is gated on `schedule` (nightly cron)
   or `workflow_dispatch`, because drift accumulates in the world while
   the repository stands still.  The job is additionally
   credential-gated: it reads the backend configuration from the
   `TERRAFORM_BACKEND_CONFIG` secret, and **skips with an explanatory
   `::notice` when the secret is absent** — honest about the fact that
   the example's `local` provider has no deployed state to compare
   against yet.  The gate becomes active the moment a backend is
   configured; nothing else has to change.

3. **[DECISION] The drift report is an incident snapshot — rendered to
   `docs/generated/drift-report.md` in the job workspace, published as a
   workflow artefact and the run summary, and never committed.**  Unlike
   the committed, drift-gated artefacts (catalog, drawio, metadata,
   composition — ADR-0012/0019/0021), the report's content depends on
   *deployed state at run time*; committing it would either break the
   committed-artefact drift gate on the next run or fossilize a stale
   snapshot in the tree.  `scripts/generate-drift-report.py` (stdlib
   only, schema `drift-report-v1`, 42-check selftest) renders the plan
   deterministically: refresh-detected state mismatches
   (`resource_drift`), planned changes classified
   replace/delete/update/create/read (`resource_changes`), per-resource
   attribute diffs with sensitive values masked and apply-time values
   marked `(known after apply)`.  Because it is never committed, the
   report is excluded from the MkDocs nav — the strict build must not
   depend on an artefact that exists only on drift.

4. **[DECISION] Drift fails the pipeline; exit code 1 (plan error)
   fails it too.**  Exit `2` renders the report, uploads it
   (30-day retention), appends it to the run summary, and then fails
   the job with a pointer to the artefact — the human-readable diff the
   issue requires is unmissable.  Exit `1` (backend unreachable,
   credentials stale) is an operational failure, not a clean "in sync",
   and must not be mistaken for one.

## Consequences

### Positive

- The pipeline can tell "code and world agree" from "they have diverged",
  on a schedule that matches how drift actually appears.
- Zero new toolchain: reuses the pinned Terraform, the stdlib-generator
  pattern (ADR-0018/0021/0022), and the existing workflow artefact
  plumbing.
- The report is safe by construction: sensitive values are masked,
  nothing is committed, the secret never leaves the job.
- The skip path is explicit and observable (`::notice`), not a silent
  green check.

### Negative / Trade-offs

- Until a remote backend is configured (issue #2), the job always takes
  the skip path — the gate is wired and self-tested, but not yet
  *exercised* against real state.  The ADR records this honestly rather
  than faking a drift signal.
- A nightly run republishes GitHub Pages even when nothing changed —
  accepted as a nightly determinism proof of the whole pipeline.
- Drift reconciliation is manual: the runbook points operators at the
  report, but the pipeline does not (and should not) auto-apply.

## Alternatives Considered

- **driftctl / cloud inventory tools** — rejected: second source of
  truth, extra dependency, per-provider coverage gaps; `terraform plan`
  already is the comparison.
- **Run on every push** — rejected: drift is not caused or fixed by a
  commit; PR runs would skip 100% of the time and add noise.
- **Commit the report** — rejected: breaks the committed-artefact drift
  gate and pollutes the deterministic tree with world-dependent bytes.
- **Separate workflow file** — rejected: one pipeline, one file
  (ADR-0002); the job-level `if:` gate keeps the schedule scoped to
  this job alone.

## Related

- [ADR-0001](0001-use-terraform-for-iac.md) — Terraform as the single
  infrastructure source of truth; drift detection is its guard rail.
- [ADR-0002](0002-use-opa-for-policy.md) — governs the pipeline workflow
  hosting the `drift-check` job and the nightly schedule.
- [ADR-0012](0012-machine-readable-adr-traceability.md) and
  [ADR-0018](0018-spectree-specification-first-ingestion.md) — the
  determinism bar the renderer follows.
- Requirement [OPS-004](../requirements/moscow.md) — this decision
  satisfies it.
