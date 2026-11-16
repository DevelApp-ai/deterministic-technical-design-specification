---
id: ADR-0017
title: Use C4Sharp for C4 Architecture Diagrams from .NET Code
status: Accepted
date: 2026-11-16
author: platform-team
tags: [dotnet, c4, c4sharp, mermaid, architecture, diagrams, documentation-as-code]
supersedes: []
related_requirements: [APP-006, M-005]
governs: [dotnet/tools/MyApp.Architecture.Diagrams/, scripts/generate-c4-diagram-docs.py, docs/generated/architecture/, docs/application/architecture-diagrams.md]
---

# ADR-0017 — Use C4Sharp for C4 Architecture Diagrams from .NET Code

## Status

Accepted

## Context

ADR-0005 settled how the *infrastructure* architecture is documented:
Mermaid embedded in Markdown, rendered client-side by MkDocs.  For the .NET
application layer the same principle applies with one addition — the C4
model of the application (its systems, containers, and components) is
knowledge that lives in the C# code itself, so it should be **declared as
code and rendered**, not hand-drawn as Mermaid text that reviewers must
keep in sync with the layering the NetArchTest policies (ADR-0014) enforce.

## Decision

Adopt **C4Sharp** (pinned 8.1.204) in the console tool
`dotnet/tools/MyApp.Architecture.Diagrams`:

1. The C4 model is declared in C# as `DiagramBuilder` subclasses —
   Context, Container, and Component diagrams of the example application,
   reviewable in pull requests like any other code.
2. The tool exports **Mermaid** sources (`C4Context`/`C4Container`/`C4Component`
   via `PlantumlContext.UseDiagramMermaidBuilder()`) to
   `docs/generated/architecture/`, plus PlantUML sources for PlantUML-based
   tooling.
3. `scripts/generate-c4-diagram-docs.py` embeds the generated Mermaid
   verbatim into the published page
   `docs/application/architecture-diagrams.md`, rendered client-side —
   consistent with ADR-0005's publishing path.
4. Output is deterministic (verified byte-identical across repeated runs)
   and git-ignored; the committed page is regenerated on every pipeline run.

This ADR extends ADR-0005 to the .NET layer; it does not supersede it —
the rendering principle (Mermaid in MkDocs) is unchanged, only the
authoring path (model-as-code over hand-written Mermaid).

## Consequences

### Positive

- The diagrams and the architecture policies describe the same structure —
  a change that violates APP-ARCH-001/002 or APP-SEC-001 cannot slip past
  reviewers as a diagram-only edit, because the model is code in the same
  pull request.
- Generated artefacts cannot drift from the declared model; the assembler
  fails loudly on missing or unregistered diagram files.
- Both Mermaid (for the site) and PlantUML (for documentation toolchains
  that prefer it) come from one declaration.

### Negative / Trade-offs

- One more .NET project and tool dependency in the solution; accepted for
  the reviewability of a code-declared model.
- Mermaid's C4 syntax is less feature-rich than Structurizr; C4Sharp's
  Mermaid builder covers the subset the site needs.

## Alternatives Considered

| Alternative | Pros | Cons / Rejected Because |
|-------------|------|------------------------|
| Hand-written Mermaid (ADR-0005 style) | Zero tooling | Model duplicated in prose/diagram text; drifts from the C# layering silently |
| Structurizr DSL | Full C4 fidelity | Separate runtime + language; no native Mermaid export for MkDocs |
| PlantUML C4 directly | Mature C4 support | Hand-authored again — same drift risk; rendered client-side less cleanly in MkDocs |
| drawio XML | Visual editing | Binary-ish diffs; cannot be generated from or reviewed against code |

## Related

- [ADR-0005 — Mermaid for Architecture Diagrams](0005-architecture-documentation.md)
- [ADR-0014 — NetArchTest Architecture Policies](0014-netarchtest-architecture-policies.md)
- MoSCoW requirements: [APP-006](../requirements/moscow.md#should-have--application-layer-net)
