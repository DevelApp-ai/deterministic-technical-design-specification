# Backstage MCP Server

The **Model Context Protocol (MCP)** is an open standard (introduced by Anthropic,
November 2024) that lets AI coding assistants and autonomous agents query external
data sources using a standardised protocol.

This page explains how the DTDS Backstage portal exposes its catalog data via an
MCP server so that AI agents (GitHub Copilot, Claude, Cursor, custom automation)
can answer questions about the system — its services, policies, documentation, and
infrastructure — without human copy-paste.

---

## What Is MCP?

```mermaid
flowchart LR
    DEV["👤 Developer"]
    AI["🤖 AI Agent\n(Copilot / Claude / Cursor)"]
    MCP["MCP Client\n(stdio transport)"]
    SERVER["MCP Server\n(npx backstage-example)"]
    BKSTG["Backstage REST API\nhttp://localhost:7007"]
    CATALOG["Catalog\nEntities"]
    TECHDOCS["TechDocs\nMetadata"]
    SEARCH["Full-text\nSearch"]

    DEV -->|"What OPA policies cover K8s?"| AI
    AI --> MCP
    MCP -->|"list_catalog_entities\nkind=Component"| SERVER
    SERVER --> BKSTG
    BKSTG --> CATALOG
    BKSTG --> TECHDOCS
    BKSTG --> SEARCH
    SERVER -->|"Structured entity data"| MCP
    MCP -->|"Context injected"| AI
    AI -->|"K8S-001 (no privileged), K8S-002 (limits), K8S-003 (labels) — see ADR-0008"| DEV
```

MCP uses a **client-server** model:
- **MCP server** — a process that exposes Backstage data as tools and resources
- **MCP client** — the AI agent's host (VS Code, Claude Desktop, Cursor)
- **Transport** — `stdio` for local development (the npx process is a child of the AI client)

---

## MCP Tools Available

The DTDS Backstage MCP server exposes three tools AI agents can call:

| Tool | What AI agents can do |
|------|-----------------------|
| `list_catalog_entities` | "List all Components owned by platform-team" / "Find all APIs tagged `ai-ready`" |
| `get_catalog_entity_by_ref` | "Get the full metadata for `component:default/deterministic-docs-example`" |
| `search_catalog_entities` | "Search for anything related to OPA policies" / "Find documentation about Kubernetes" |

### Example AI agent conversations

**Q:** "What services are registered in the catalog?"
```
→ list_catalog_entities(filter: kind=Component)
← [deterministic-docs-example, dtds-backstage-portal]
```

**Q:** "What APIs does the platform expose?"
```
→ list_catalog_entities(filter: kind=API)
← [dtds-backstage-api] — REST + MCP, OpenAPI definition inline
```

**Q:** "What OPA policies apply to Kubernetes workloads?"
```
→ search_catalog_entities(term: "Kubernetes OPA policy")
← TechDocs hit: docs/kubernetes/index.md → K8S-001, K8S-002, K8S-003
→ get_catalog_entity_by_ref(ref: component:default/deterministic-docs-example)
← annotations.dtds/related_requirements: "K-001,K-002,K-003"
```

**Q:** "Who owns the deterministic docs system?"
```
→ get_catalog_entity_by_ref(ref: system:default/deterministic-docs)
← spec.owner: group:default/platform-team
```

---

## Quick Start

### Prerequisites

- Docker (to run the Backstage portal)
- Node.js ≥ 18 (for `npx`)
- A supported AI client: VS Code with GitHub Copilot, Claude Desktop, or Cursor

### Step 1 — Start Backstage

```bash
# Build the image (first time: ~8-12 min)
docker build -f example/Dockerfile.backstage -t dtds-backstage example/

# Run with the MCP token
docker run --rm -p 7007:7007 \
  -e BACKSTAGE_MCP_TOKEN=dtds-mcp-demo-token-change-in-production \
  -e GITHUB_TOKEN=${GITHUB_TOKEN:-} \
  dtds-backstage
```

Verify the catalog is up:
```bash
curl -s http://localhost:7007/api/catalog/entities \
  -H "Authorization: Bearer dtds-mcp-demo-token-change-in-production" \
  | python3 -m json.tool | grep '"name"' | head -10
```

Expected output (7 entities):
```
"name": "platform-team",
"name": "platform-lead",
"name": "deterministic-docs",
"name": "deterministic-docs-example",
"name": "dtds-backstage-portal",
"name": "dtds-backstage-api",
"name": "dtds-github-pages",
```

### Step 2 — Configure Your AI Client

=== "VS Code / GitHub Copilot"

    The project already ships `.vscode/mcp.json`.  In VS Code, open the Command
    Palette (`Ctrl+Shift+P`) and run **MCP: List Servers** to see
    `dtds-backstage` listed and active.

    If you need to set it manually, the content is:

    ```json
    {
      "servers": {
        "dtds-backstage": {
          "type": "stdio",
          "command": "npx",
          "args": ["-y", "@modelcontextprotocol/server-mcp-backstage-example-evanshortiss"],
          "env": {
            "BACKSTAGE_BASE_URL": "http://localhost:7007",
            "BACKSTAGE_API_TOKEN": "dtds-mcp-demo-token-change-in-production"
          }
        }
      }
    }
    ```

=== "Claude Desktop"

    Merge `backstage/mcp-clients/claude-desktop.json` into your Claude Desktop
    configuration file:

    - **macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`
    - **Windows**: `%APPDATA%\Claude\claude_desktop_config.json`

    Then restart Claude Desktop.  You will see `dtds-backstage` in the
    Available Tools panel.

=== "Cursor"

    Merge `backstage/mcp-clients/cursor-mcp.json` into `~/.cursor/mcp.json`
    (global) or `.cursor/mcp.json` (project-level).  Restart Cursor.

### Step 3 — Ask Your AI Agent

In VS Code Chat, Claude, or Cursor:

```
@dtds-backstage What components are registered in the catalog?
```

```
@dtds-backstage Which API exposes the Backstage MCP interface?
```

```
@dtds-backstage Find documentation about the OPA Kubernetes policies.
```

---

## Catalog Entity Hierarchy

The `catalog-info.yaml` now registers seven entities.  AI agents can traverse
the hierarchy to understand system ownership, dependencies, and interfaces:

```mermaid
graph TD
    SYS["🏗️ System\ndeterministic-docs"]
    GRP["👥 Group\nplatform-team"]
    USR["👤 User\nplatform-lead"]
    COMP1["📦 Component\ndeterministic-docs-example\n(documentation pipeline)"]
    COMP2["📦 Component\ndtds-backstage-portal\n(developer portal)"]
    API["🔌 API\ndtds-backstage-api\n(REST + MCP)"]
    RES1["💾 Resource\ndtds-github-pages\n(published site)"]
    RES2["💾 Resource\ndtds-docker-toolchain\n(build image)"]

    SYS --> COMP1
    SYS --> COMP2
    SYS --> API
    SYS --> RES1
    SYS --> RES2
    GRP --> USR
    COMP1 -->|"providesApis"| API
    COMP2 -->|"providesApis"| API
    COMP1 -->|"dependsOn"| RES1
    COMP1 -->|"dependsOn"| RES2
```

---

## Authentication

| Environment | Token Source | How to Set |
|-------------|-------------|------------|
| Demo / local | Default value in `app-config.yaml` | None — works out of the box |
| Development | `BACKSTAGE_MCP_TOKEN` env var | `docker run -e BACKSTAGE_MCP_TOKEN=<secret> …` |
| Production | Secrets manager (Vault, AWS SSM, etc.) | Inject at container startup; never commit tokens |

!!! warning "Demo Token"
    The default token `dtds-mcp-demo-token-change-in-production` is intentionally
    visible in this showcase to enable zero-config local use.  Replace it before
    deploying to any shared or production environment.

---

## Traceability

| Artefact | Purpose |
|----------|---------|
| `catalog-info.yaml` | Multi-document entity registry (System, Group, User, Component × 2, API, Resource × 2) |
| `backstage/app-config.yaml` | Static token auth (`backend.auth.externalAccess`) for MCP |
| `.vscode/mcp.json` | VS Code / GitHub Copilot MCP config (committed, works out of the box) |
| `backstage/mcp-clients/claude-desktop.json` | Claude Desktop MCP config snippet |
| `backstage/mcp-clients/cursor-mcp.json` | Cursor MCP config snippet |
| ADR | [ADR-0009](../../adrs/0009-backstage-mcp-server.md) |
| Requirements | [AI-001, AI-002, AI-003](../../requirements/moscow.md#should-have--ai--mcp-integration) |
