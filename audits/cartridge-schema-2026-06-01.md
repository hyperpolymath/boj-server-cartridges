# Cartridge manifest validation report
Schema: schemas/cartridge-v1.json
Manifests: 139 total / 94 passing / 45 failing

## Top recurring issues
- 21× auth.method: value "bearer_token"
- 8× api: required field missing
- 8× auth.env_var: required field missing
- 8× auth.credential_source: required field missing
- 6× protocols: required field missing
- 5× tools[0].inputSchema: required field missing
- 5× tools[1].inputSchema: required field missing
- 5× tools[2].inputSchema: required field missing
- 5× tools[3].inputSchema: required field missing
- 5× tools[4].inputSchema: required field missing
- 5× auth.method: value "api_key"
- 2× auth.method: value "api_key_header"
- 2× tools[5].inputSchema: required field missing
- 1× auth.method: value "session-token"
- 1× name: value "boj-health"

## Per-manifest failures

### cartridges/cross-cutting/agentic/claude-ai-mcp/cartridge.json
- `auth.method` — value "api_key_header" not in enum ["none","api-key","oauth2","vault"]

### cartridges/cross-cutting/agentic/local-coord-mcp/cartridge.json
- `auth.method` — value "session-token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/cross-cutting/health/boj-health/cartridge.json
- `name` — value "boj-health" does not match pattern /^[a-z0-9]+(-[a-z0-9]+)*-(mcp|lsp|dap|bsp|debug|format|lint|build|nesy|agentic|fleet)$/

### cartridges/domains/bioinformatics/origenemcp/cartridge.json
- `name` — value "origenemcp" does not match pattern /^[a-z0-9]+(-[a-z0-9]+)*-(mcp|lsp|dap|bsp|debug|format|lint|build|nesy|agentic|fleet)$/

### cartridges/domains/ci-cd/buildkite-mcp/cartridge.json
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/ci-cd/circleci-mcp/cartridge.json
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/ci-cd/github-actions-mcp/cartridge.json
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/cloud/cloudflare-mcp/cartridge.json
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/cloud/digitalocean-mcp/cartridge.json
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/cloud/fly-mcp/cartridge.json
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/cloud/hetzner-mcp/cartridge.json
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/cloud/linode-mcp/cartridge.json
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/cloud/railway-mcp/cartridge.json
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/cloud/render-mcp/cartridge.json
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

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

### cartridges/domains/container/docker-hub-mcp/cartridge.json
- `auth.method` — value "bearer" not in enum ["none","api-key","oauth2","vault"]

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

### cartridges/domains/formal-verification/echidna-llm-mcp/cartridge.json
- `auth.method` — value "api_key_header" not in enum ["none","api-key","oauth2","vault"]

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

### cartridges/domains/knowledge/obsidian-mcp/cartridge.json
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/multimodal/elevenlabs-mcp/cartridge.json
- `auth.method` — value "api_key" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/multimodal/replicate-mcp/cartridge.json
- `auth.method` — value "api_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/multimodal/whisper-mcp/cartridge.json
- `auth.method` — value "optional_api_key" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/observability/grafana-mcp/cartridge.json
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/observability/prometheus-mcp/cartridge.json
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/observability/sentry-mcp/cartridge.json
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/open-data/opendatamcp/cartridge.json
- `name` — value "opendatamcp" does not match pattern /^[a-z0-9]+(-[a-z0-9]+)*-(mcp|lsp|dap|bsp|debug|format|lint|build|nesy|agentic|fleet)$/

### cartridges/domains/productivity/airtable-mcp/cartridge.json
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/productivity/todoist-mcp/cartridge.json
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/registry/crates-mcp/cartridge.json
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/registry/hackage-mcp/cartridge.json
- `auth.method` — value "basic" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/registry/hex-mcp/cartridge.json
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/registry/npm-registry-mcp/cartridge.json
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/registry/pypi-mcp/cartridge.json
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

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

### cartridges/domains/research/search-mcp/cartridge.json
- `auth.method` — value "api_key" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/research/zotero-mcp/cartridge.json
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/vector/chromadb-mcp/cartridge.json
- `auth.method` — value "optional_bearer" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/vector/pinecone-mcp/cartridge.json
- `auth.method` — value "api_key" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/vector/qdrant-mcp/cartridge.json
- `auth.method` — value "api_key" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/vector/weaviate-mcp/cartridge.json
- `auth.method` — value "api_key" not in enum ["none","api-key","oauth2","vault"]
