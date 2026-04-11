---
id: ADR-0005
title: Use Mermaid Embedded in Markdown for Architecture Diagrams
status: Accepted
date: 2024-03-20
author: platform-team
tags: [architecture, diagrams, mermaid, c4, documentation-as-code]
supersedes: []
related_requirements: [M-005, A-001, A-002, A-003]
---

# ADR-0005 — Use Mermaid Embedded in Markdown for Architecture Diagrams

## Status

Accepted

## Context

Architecture documentation requires diagrams — C4 models, data flow diagrams,
sequence diagrams, and technology radars.  Traditional approaches involve:

- **Diagramming tools** (draw.io, Lucidchart, Miro): Files are binary or XML
  blobs that cannot be diffed, reviewed, or generated from source code.
- **PlantUML**: Requires a server or Java runtime; generates PNG/SVG outputs
  that are checked into git as binary artefacts.
- **Structurizr DSL**: Full C4 model fidelity but requires a separate
  runtime or cloud service.

The deterministic documentation principle requires that diagrams must be
**generated from code** or at minimum **version-controlled as text** so they
can be reviewed in pull requests.

## Decision

All architecture diagrams will use **Mermaid** syntax embedded directly in
Markdown files.  MkDocs Material renders Mermaid client-side (no server
required).  The supported diagram types are:

| Diagram Type | Mermaid Type | Use Case |
|-------------|-------------|---------|
| C4 Context | `C4Context` | System boundary and actors |
| C4 Container | `C4Container` | Deployable units |
| C4 Component | `C4Component` | Internal structure of containers |
| Data Flow | `flowchart` | How artefacts move through the pipeline |
| Sequence | `sequenceDiagram` | CI/CD job ordering and interactions |
| Entity Relationship | `erDiagram` | Data model documentation |

Architecture diagrams live in `docs/architecture/index.md`.  The technology
radar is maintained as a Markdown table in the same file.

Quality attribute scenarios are captured in the architecture page using a
structured table format that can be parsed by tooling.

## Consequences

### Positive

- Diagrams are plain text — fully diff-able and code-reviewable.
- No external tool, server, or licence required.
- MkDocs Material renders Mermaid client-side in the browser.
- C4 diagram types (`C4Context`, `C4Container`, `C4Component`) provide
  industry-standard architecture views without Structurizr.
- Technology radar is a Markdown table — trivially parseable by scripts.

### Negative / Trade-offs

- Mermaid's C4 support is less feature-rich than Structurizr DSL.
- Large or complex diagrams can become hard to read in raw Markdown.
- Mermaid diagrams cannot be embedded in Word/PDF without a separate
  render step.

## Alternatives Considered

| Alternative | Rejected Because |
|-------------|-----------------|
| draw.io XML in git | Binary-ish diffs; cannot be auto-generated |
| Structurizr DSL | Requires separate runtime; no native MkDocs integration |
| PlantUML | Requires Java or server; generates binary PNG outputs |
| Graphviz DOT | Powerful but low-level; no C4 model support |

## Related

- [ADR-0003 — MkDocs for Publishing](0003-use-mkdocs-for-publishing.md)
- MoSCoW requirements: [A-001, A-002, A-003](../requirements/moscow.md#should-have)
