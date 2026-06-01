# Cartridge manifest validation report
Schema: schemas/cartridge-v1.json
Manifests: 139 total / 136 passing / 3 failing

## Top recurring issues
- 1× name: value "boj-health"
- 1× name: value "origenemcp"
- 1× name: value "opendatamcp"

## Per-manifest failures

### cartridges/cross-cutting/health/boj-health/cartridge.json
- `name` — value "boj-health" does not match pattern /^[a-z0-9]+(-[a-z0-9]+)*-(mcp|lsp|dap|bsp|debug|format|lint|build|nesy|agentic|fleet)$/

### cartridges/domains/bioinformatics/origenemcp/cartridge.json
- `name` — value "origenemcp" does not match pattern /^[a-z0-9]+(-[a-z0-9]+)*-(mcp|lsp|dap|bsp|debug|format|lint|build|nesy|agentic|fleet)$/

### cartridges/domains/open-data/opendatamcp/cartridge.json
- `name` — value "opendatamcp" does not match pattern /^[a-z0-9]+(-[a-z0-9]+)*-(mcp|lsp|dap|bsp|debug|format|lint|build|nesy|agentic|fleet)$/
