---
id: ADR-0016
title: Use Roslyn Analyzers as the .NET Code-Quality Gate
status: Accepted
date: 2026-11-16
author: platform-team
tags: [dotnet, roslyn, analyzers, code-quality, static-analysis]
supersedes: []
related_requirements: [APP-003, APP-004]
governs: [dotnet/Directory.Build.props, dotnet/.editorconfig]
---

# ADR-0016 — Use Roslyn Analyzers as the .NET Code-Quality Gate

## Status

Accepted

## Context

The deterministic pipeline requires that documentation is generated only
from a *compliant* build — the DocFX reference, the OpenAPI document, and
the published policy pages all inherit the quality of the compiled code.
For the .NET layer this means the build itself must enforce code-quality and
security rules, deterministically, on every machine and CI runner.

Style rules enforced only by IDE tooling fail on the first contributor who
configures their editor differently.  A quality gate must be part of the
build, not a suggestion in the IDE.

## Decision

Adopt the **Roslyn analyzer stack** wired into the build itself — all three
packages referenced from `dotnet/Directory.Build.props` with
`PrivateAssets="all"`, so they apply to every project in the solution:

1. **`Microsoft.CodeAnalysis.NetAnalyzers` 11.0.100** — the platform
   baseline quality and security rules (supersedes FxCop).
2. **`Roslynator.Analyzers` 5.0.1** — additional code-quality and style
   rules.
3. **`SonarAnalyzer.CSharp` 10.36.0.15337** — security and code-smell
   detection (as a build-time analyzer, no SonarQube server needed).

Enforcement mechanics, version-controlled in `dotnet/.editorconfig`:

| Severity | Meaning | Examples |
|----------|---------|----------|
| `error` | Security-critical findings | CA3001–CA3011, CA3075, CA5359, CA5364, S2077, S2068, S2257, S4830, S5332, S5766 |
| `warning` | Quality findings | CA1031, CA1062, CA1303, CA2000, S1066, S109, RCS1062/1032/1124 |
| `suggestion` | Style preferences | RCS1001/1214/1194, S1135 (suppressed for "todo" domain vocabulary) |

`TreatWarningsAsErrors` (Directory.Build.props) turns every warning-severity
finding into a build failure: **the gate is blocking by design** — a build
with an analyzer violation produces no artefacts for the documentation
pipeline to consume.

## Consequences

### Positive

- The gate runs on every `dotnet build`, everywhere — local machines and CI
  are indistinguishable (together with the pinned SDK via `global.json`, this
  closes APP-004).
- Findings are actionable in the IDE *and* blocking in CI — the same rules.
- No external server or licence: all three packages are analyzers running
  inside the compiler.

### Negative / Trade-offs

- Build time increases with the analyzer surface; mitigated by incremental
  compilation.
- Severity tuning is a living decision: escalating a rule is a one-line
  `.editorconfig` change, but it fails every current violation at once —
  rules are tuned in small PRs, as done for S2068 during adoption.

## Alternatives Considered

| Alternative | Pros | Cons / Rejected Because |
|-------------|------|------------------------|
| StyleCop only | Style enforcement | No security rules; no blocking severity model |
| SonarQube server | Dashboards, quality gates | Separate server + licence; the gate must live in the build |
| `.editorconfig` IDE hints only | Zero friction | Not machine-enforceable; depends on each developer's setup |
| No enforcement | None | The documentation pipeline would publish from non-compliant builds |

## Related

- [ADR-0014 — NetArchTest Architecture Policies](0014-netarchtest-architecture-policies.md)
- [ADR-0007 — Semantic Versioning](0007-semantic-versioning-and-changelog.md)
- MoSCoW requirements: [APP-003, APP-004](../requirements/moscow.md#must-have)
