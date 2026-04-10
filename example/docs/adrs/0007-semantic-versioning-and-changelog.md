---
id: ADR-0007
title: Adopt Semantic Versioning and Auto-generated Changelog
status: Accepted
date: 2024-04-01
author: platform-team
tags: [versioning, changelog, semantic-versioning, git-cliff, ci]
supersedes: []
related_requirements: [V-001, V-002, V-003]
---

# ADR-0007 — Adopt Semantic Versioning and Auto-generated Changelog

## Status

Accepted

## Context

Without a versioning strategy the documentation site has no stable
reference point.  Consumers cannot pin to a known-good version, and the
team has no automated record of what changed between releases.

Manual changelogs drift or go unmaintained.  Conventional-commit message
parsing enables the changelog to be generated **deterministically** from
the git history, eliminating the need for hand-written release notes.

## Decision

1. **Semantic versioning** — the canonical version is maintained in
   `version.txt` (single source of truth).  The CI `release` job reads
   this file, tags the commit `v<version>`, and publishes the artefact.

2. **Conventional commits** are enforced as the commit message format:
   ```
   <type>(<scope>): <description>

   [optional body]

   [optional footer(s)]
   ```
   Allowed types: `feat`, `fix`, `docs`, `perf`, `refactor`, `style`,
   `test`, `chore`, `ci`, `revert`.

3. **git-cliff** (`cliff.toml`) generates `CHANGELOG.md` on every
   release from the conventional-commit history.  The changelog is
   committed back to the branch, and the rendered version is published
   inside the MkDocs site at `docs/versioning/CHANGELOG.md`.

4. The MkDocs site embeds the current version in its footer via the
   `extra.version` variable read from `version.txt` at build time.

## Version Bump Workflow

```
Developer updates version.txt → commits with "chore(release): bump to v1.2.0"
CI release job:
  1. Read version from version.txt
  2. Run git-cliff → generate / update CHANGELOG.md
  3. Commit CHANGELOG.md
  4. Tag commit v1.2.0
  5. Push tag → GitHub Release created automatically
  6. docs-build picks up new tag → site footer shows v1.2.0
```

## Consequences

### Positive

- Single source of truth (`version.txt`) — no version scattered across
  multiple files.
- Changelog is generated automatically; no manual release notes needed.
- Consumers can reference specific site versions via git tags.
- `cliff.toml` is version-controlled — changelog format is auditable.

### Negative / Trade-offs

- Developers must use conventional commit format; free-form messages are
  filtered out of the changelog.
- Initial adoption requires re-training the team on commit message style.
- git-cliff must be installed in the CI image; pinned version avoids
  non-determinism.

## Alternatives Considered

| Alternative | Rejected Because |
|-------------|-----------------|
| Manual `CHANGELOG.md` | Prone to neglect; non-deterministic |
| `standard-version` (Node.js) | Requires Node runtime; heavier dependency |
| GitHub Release notes auto-generate | Tied to GitHub UI; not reproducible locally |
| `semantic-release` | Opinionated; requires npm; over-engineered for a docs repo |

## Related

- [ADR-0003 — MkDocs for Publishing](0003-use-mkdocs-for-publishing.md)
- MoSCoW requirements: [V-001, V-002, V-003](../requirements/moscow.md#should-have--versioning--changelog)
