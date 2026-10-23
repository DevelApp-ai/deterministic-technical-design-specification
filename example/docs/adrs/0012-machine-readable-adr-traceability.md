---
id: ADR-0012
title: Machine-Readable ADR Traceability Kit
status: Accepted
date: 2026-10-23
author: platform-team
tags: [adr, traceability, policy-as-code, ci-gate, drawio]
supersedes: []
related_requirements: [S-006, M-005, D-001]
governs: [policies/architecture/, scripts/scan-architecture.py, scripts/generate-traceability.py, scripts/architecture-gate.sh, scripts/architecture-demo.sh, scripts/architecture-demo-fixtures/, docs/generated/architecture-catalog.json, docs/generated/traceability.drawio, docs/adrs/0012-machine-readable-adr-traceability.md]
---

# ADR-0012 — Machine-Readable ADR Traceability Kit

## Status

Accepted

## Context

The estate's architecture decisions live in `docs/adrs/` as markdown with
YAML front-matter, and every Rego policy carries a `__rego__metadoc__` block
that cites its governing ADR.  That substrate is rich, but it is inert:

1. **Supersede chains are traversed by hand.**  When ADR-0009 supersedes
   ADR-0004, a reader must follow the `supersedes` refs themselves; nothing
   resolves "what is the *current* decision on X?"
2. **Traceability is hand-maintained.**  `docs/traceability/index.md` is a
   stale, hand-drawn diagram; it already predates ADR-0010 and ADR-0011.
3. **Decisions have no territory.**  Nothing fails a pull request that
   changes a boundary-affecting file (say `policies/` or `terraform/`)
   without citing the ADR that governs it.  The decision record and the
   change stream are disconnected.

The doc-coverage gate (ADR-0006) protects documentation currency; no
comparable gate protects *decision* currency.

## Decision

Adopt a four-part traceability kit, all under `example/`:

1. **Catalog** — `scripts/scan-architecture.py` extracts ADR front-matter,
   policy metadoc blocks, and MoSCoW requirement ids into a single
   machine-readable catalog, `docs/generated/architecture-catalog.json`.
   The scan is metadata-only (front-matter and metadoc literals, no
   semantic analysis) and byte-deterministic across runs.
2. **Policies** — `policies/architecture/` consumes the catalog:
   - `validate.rego` — loud findings over the catalog itself: duplicate
     ADR ids, unknown or cyclic `supersedes` refs, status/chain
     mismatches, ADRs without requirements or governed paths, dangling
     requirement refs, policy metadoc defects.  Every finding carries a
     severity, a rule name, a message, and a JSON path back into the
     catalog.
   - `chain.rego` — supersede-chain traversal: `effective[id]` resolves
     the current ADR of each decision.  Rego forbids recursion, so the
     traversal is a bounded 8-hop closure with an explicit
     still-growing check (`catalog/chain-depth-exceeded`); the cap is
     loud, never silent.  (`graph.reachable` is deliberately not used:
     in OPA 0.69 it stops after one hop when the graph object is
     produced by a rule rather than a literal.)
   - `gate.rego` — the PR boundary gate: a changed path governed by an
     Accepted ADR requires that ADR (id cited in the PR description)
     to be linked, or the gate fails and names the governing ADRs.
     Links to superseded ADRs are rejected and redirected to the
     successor resolved by the chain traversal.
3. **Generator** — `scripts/generate-traceability.py` regenerates
   `docs/generated/traceability.drawio`, a book-convention drawio diagram
   (MoSCoW → ADR → policy → implementation columns, supersede edges
   dashed red) from the catalog, byte-identically across runs.  The
   hand-drawn mermaid in `docs/traceability/index.md` becomes historical.
4. **CI gate** — `scripts/architecture-gate.sh` runs scan → validate →
   gate on every pull request (`architecture` job in the pipeline), and
   `scripts/architecture-demo.sh` proves the done-when scenario
   end-to-end with inverted expectations: a boundary change is blocked
   without a linked ADR and passes with one, the traceability diagram
   regenerates byte-identically.

## Consequences

### Positive

- Supersede chains are machine-traversed; "what is the current decision?"
  has one authoritative answer (`chain.effective`).
- The traceability diagram can never silently drift — it is regenerated
  from the same catalog the policies validate.
- A boundary-affecting change without a decision record is a red PR,
  with a message that names the ADR to cite.
- The kit is honest about its scope: a metadata scan, not semantic
  analysis; findings are loud and path-cited.

### Negative / Trade-offs

- One more PR gate to satisfy: a change under a governed path now
  *requires* citing the governing ADR id in the PR description.
- Chains deeper than seven supersede hops are rejected, not traversed
  (flagged as `catalog/chain-depth-exceeded`) — a deliberate cap that
  keeps the closure non-recursive.
- ADR front-matter gains a `governs` key; ADR authors must maintain it
  (the validator flags Accepted ADRs with none).

## Alternatives Considered

| Alternative | Rejected Because |
|-------------|-----------------|
| Hand-maintained traceability page | Already stale before ADR-0010; humans forget |
| `graph.reachable` for chains | OPA 0.69 stops after one hop on rule-produced graphs |
| Semantic AST analysis of ADR prose | Out of scope; metadata is sufficient for the gate |

## Related

- [ADR-0002 — OPA for Policy](0002-use-opa-for-policy.md)
- [ADR-0006 — Documentation Coverage Gate](0006-enforce-doc-coverage-gate.md)
- MoSCoW requirements: [S-006, M-005, D-001](../requirements/moscow.md)
