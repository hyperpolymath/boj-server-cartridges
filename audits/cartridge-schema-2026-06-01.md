# Cartridge manifest validation report
Schema: schemas/cartridge-v1.json
Manifests: 139 total / 128 passing / 11 failing

## Top recurring issues
- 8× api: required field missing
- 8× auth.env_var: required field missing
- 8× auth.credential_source: required field missing
- 6× protocols: required field missing
- 5× tools[0].inputSchema: required field missing
- 5× tools[1].inputSchema: required field missing
- 5× tools[2].inputSchema: required field missing
- 5× tools[3].inputSchema: required field missing
- 5× tools[4].inputSchema: required field missing
- 2× tools[5].inputSchema: required field missing
- 1× name: value "boj-health"
- 1× name: value "origenemcp"
- 1× name: value "opendatamcp"

## Per-manifest failures

### cartridges/cross-cutting/health/boj-health/cartridge.json
- `name` — value "boj-health" does not match pattern /^[a-z0-9]+(-[a-z0-9]+)*-(mcp|lsp|dap|bsp|debug|format|lint|build|nesy|agentic|fleet)$/

### cartridges/domains/bioinformatics/origenemcp/cartridge.json
- `name` — value "origenemcp" does not match pattern /^[a-z0-9]+(-[a-z0-9]+)*-(mcp|lsp|dap|bsp|debug|format|lint|build|nesy|agentic|fleet)$/

### cartridges/domains/code-quality/sanctify-mcp/cartridge.json
- `protocols` — required field missing
- `api` — required field missing
- `auth.env_var` — required field missing
- `auth.credential_source` — required field missing
- `tools[0].inputSchema` — required field missing
- `tools[1].inputSchema` — required field missing
- `tools[2].inputSchema` — required field missing
- `tools[3].inputSchema` — required field missing
- `tools[4].inputSchema` — required field missing

### cartridges/domains/development/fireflag-mcp/cartridge.json
- `protocols` — required field missing
- `api` — required field missing
- `auth.env_var` — required field missing
- `auth.credential_source` — required field missing
- `tools[0].inputSchema` — required field missing
- `tools[1].inputSchema` — required field missing
- `tools[2].inputSchema` — required field missing
- `tools[3].inputSchema` — required field missing
- `tools[4].inputSchema` — required field missing

### cartridges/domains/formal-verification/ephapax-mcp/cartridge.json
- `protocols` — required field missing
- `api` — required field missing
- `auth.env_var` — required field missing
- `auth.credential_source` — required field missing
- `tools[0].inputSchema` — required field missing
- `tools[1].inputSchema` — required field missing
- `tools[2].inputSchema` — required field missing
- `tools[3].inputSchema` — required field missing
- `tools[4].inputSchema` — required field missing

### cartridges/domains/gaming/npc-mcp/cartridge.json
- `api` — required field missing
- `auth.env_var` — required field missing
- `auth.credential_source` — required field missing

### cartridges/domains/infrastructure/hesiod-mcp/cartridge.json
- `protocols` — required field missing
- `api` — required field missing
- `auth.env_var` — required field missing
- `auth.credential_source` — required field missing

### cartridges/domains/knowledge/librarian-mcp/cartridge.json
- `api` — required field missing
- `auth.env_var` — required field missing
- `auth.credential_source` — required field missing

### cartridges/domains/open-data/opendatamcp/cartridge.json
- `name` — value "opendatamcp" does not match pattern /^[a-z0-9]+(-[a-z0-9]+)*-(mcp|lsp|dap|bsp|debug|format|lint|build|nesy|agentic|fleet)$/

### cartridges/domains/research/academic-workflow-mcp/cartridge.json
- `protocols` — required field missing
- `api` — required field missing
- `auth.env_var` — required field missing
- `auth.credential_source` — required field missing
- `tools[0].inputSchema` — required field missing
- `tools[1].inputSchema` — required field missing
- `tools[2].inputSchema` — required field missing
- `tools[3].inputSchema` — required field missing
- `tools[4].inputSchema` — required field missing
- `tools[5].inputSchema` — required field missing

### cartridges/domains/research/bofig-mcp/cartridge.json
- `protocols` — required field missing
- `api` — required field missing
- `auth.env_var` — required field missing
- `auth.credential_source` — required field missing
- `tools[0].inputSchema` — required field missing
- `tools[1].inputSchema` — required field missing
- `tools[2].inputSchema` — required field missing
- `tools[3].inputSchema` — required field missing
- `tools[4].inputSchema` — required field missing
- `tools[5].inputSchema` — required field missing
