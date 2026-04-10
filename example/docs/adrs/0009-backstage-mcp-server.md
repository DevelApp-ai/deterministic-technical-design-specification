---
id: ADR-0009
title: Expose Backstage Catalog Data via Model Context Protocol (MCP)
status: Accepted
date: 2024-04-01
author: platform-team
tags: [backstage, mcp, ai-agents, catalog, model-context-protocol]
supersedes: []
related_requirements: [AI-001, AI-002, AI-003]
---

# ADR-0009 — Expose Backstage Catalog Data via Model Context Protocol (MCP)

## Status

Accepted

## Context

The Backstage catalog contains machine-readable metadata about every service,
API, infrastructure resource, and documentation artefact in the system.  This
metadata — entity refs, ownership, lifecycle, TechDocs URLs, OPA policy links,
ADR cross-references — is exactly the kind of context that AI coding assistants
and autonomous agents need to:

- Answer questions like "what OPA policies govern the Kubernetes workloads?"
- Navigate documentation: "show me the runbook for the platform-team services"
- Perform analysis: "which components have no owner set?"
- Drive automation: "scaffold a new service that follows the platform standards"

The **Model Context Protocol (MCP)**, open-sourced by Anthropic in late 2024,
provides a standardised, transport-agnostic protocol for AI agents to access
external tools and data sources.  Rather than building per-model integrations,
a single MCP server works with any MCP-compatible client (VS Code / GitHub
Copilot, Claude Desktop, Cursor, OpenAI agents, custom automation).

## Decision

Integrate the community MCP server `evanshortiss/mcp-backstage-example`
(npm: `@modelcontextprotocol/server-mcp-backstage-example-evanshortiss`)
with the Backstage instance.

### What changes

1. **`backstage/app-config.yaml`** — adds `backend.auth.externalAccess` with
   a static bearer token so the MCP server can authenticate against the
   Backstage REST API.

2. **`.vscode/mcp.json`** — VS Code / GitHub Copilot MCP server configuration
   (project-level, committed to the repository so any developer cloning the
   repo gets MCP out of the box).

3. **`backstage/mcp-clients/`** — per-client configuration snippets for
   Claude Desktop and Cursor.

4. **`catalog-info.yaml`** — enriched from a single `Component` entity to a
   full entity hierarchy (System, Group, User, Component × 2, API, Resource × 2)
   so AI agents have richer context to query.

### MCP tools exposed

The MCP server exposes the following tools to AI agents:

| Tool | Description |
|------|-------------|
| `list_catalog_entities` | List all entities, optionally filtered by kind / type / tag |
| `get_catalog_entity_by_ref` | Fetch a single entity by its `kind:namespace/name` ref |
| `search_catalog_entities` | Full-text search across catalog and TechDocs |

### Authentication model

- **Demo/showcase** — a static token (`dtds-mcp-demo-token-change-in-production`)
  is provided in the defaults for zero-configuration local use.
- **Production** — inject `BACKSTAGE_MCP_TOKEN` (and `BACKSTAGE_API_TOKEN` in
  the MCP client config) as environment variables from a secrets manager.
  The static token subject (`mcp-server`) can be scoped to read-only permissions
  via Backstage permission policies.

## Consequences

### Positive

- AI agents (Copilot, Claude, Cursor, custom) can query the full service catalog
  with natural-language questions without custom integration code.
- Zero additional runtime processes: the MCP server is an `npx`-invoked
  child process — no separate container or service to deploy.
- Committed client configs (`.vscode/mcp.json`) mean every developer gets
  catalog-aware AI assistance immediately after cloning.
- Enriched catalog (System, API, Resource, Group, User entities) provides
  richer context for both AI agents and human browsing.

### Negative / Trade-offs

- The static demo token must be rotated before any production deployment.
- The community MCP server supports catalog and search only; TechDocs content
  search returns metadata, not rendered HTML.
- Node.js is required on the developer's machine to run `npx`; this is already
  a common prerequisite for most development environments.

## Alternatives Considered

| Alternative | Notes |
|-------------|-------|
| Custom MCP server from scratch | Full control but large build effort; community server already covers the key use cases |
| Backstage frontend MCP plugin (`automationpi/backstage-plugin-mcp-frontend`) | Visualises MCP entities in Backstage UI; complementary, not a replacement |
| Expose Backstage REST API directly (no MCP) | Works but requires per-model integration code; MCP provides standardised client support |
| Backstage search plugin proxy | Sufficient for text search but not for structured entity queries |

## Related

- [ADR-0003 — MkDocs for Publishing](0003-use-mkdocs-for-publishing.md)
- Community MCP server: <https://github.com/evanshortiss/mcp-backstage-example>
- MCP specification: <https://spec.modelcontextprotocol.io/>
- MoSCoW requirements: [AI-001, AI-002, AI-003](../requirements/moscow.md#should-have--ai--mcp-integration)
