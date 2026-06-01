# Cartridge manifest validation report
Schema: schemas/cartridge-v1.json
Manifests: 139 total / 12 passing / 127 failing

## Top recurring issues
- 127× category: required field missing
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

## Per-manifest failures

### cartridges/cross-cutting/agentic/agent-mcp/cartridge.json
- `category` — required field missing

### cartridges/cross-cutting/agentic/claude-agents-power-mcp/cartridge.json
- `category` — required field missing

### cartridges/cross-cutting/agentic/claude-ai-mcp/cartridge.json
- `category` — required field missing
- `auth.method` — value "api_key_header" not in enum ["none","api-key","oauth2","vault"]

### cartridges/cross-cutting/agentic/local-coord-mcp/cartridge.json
- `category` — required field missing
- `auth.method` — value "session-token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/cross-cutting/agentic/model-router-mcp/cartridge.json
- `category` — required field missing

### cartridges/cross-cutting/build/bsp-mcp/cartridge.json
- `category` — required field missing

### cartridges/cross-cutting/debug/dap-mcp/cartridge.json
- `category` — required field missing

### cartridges/cross-cutting/fleet/fleet-mcp/cartridge.json
- `category` — required field missing

### cartridges/cross-cutting/health/boj-health/cartridge.json
- `category` — required field missing
- `name` — value "boj-health" does not match pattern /^[a-z0-9]+(-[a-z0-9]+)*-(mcp|lsp|dap|bsp|debug|format|lint|build|nesy|agentic|fleet)$/

### cartridges/cross-cutting/nesy/ml-mcp/cartridge.json
- `category` — required field missing

### cartridges/cross-cutting/nesy/nesy-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/automation/browser-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/bioinformatics/origenemcp/cartridge.json
- `category` — required field missing
- `name` — value "origenemcp" does not match pattern /^[a-z0-9]+(-[a-z0-9]+)*-(mcp|lsp|dap|bsp|debug|format|lint|build|nesy|agentic|fleet)$/

### cartridges/domains/ci-cd/buildkite-mcp/cartridge.json
- `category` — required field missing
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/ci-cd/circleci-mcp/cartridge.json
- `category` — required field missing
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/ci-cd/github-actions-mcp/cartridge.json
- `category` — required field missing
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/ci-cd/hypatia-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/ci-cd/laminar-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/cloud/aws-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/cloud/cloud-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/cloud/cloudflare-mcp/cartridge.json
- `category` — required field missing
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/cloud/digitalocean-mcp/cartridge.json
- `category` — required field missing
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/cloud/fly-mcp/cartridge.json
- `category` — required field missing
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/cloud/gcp-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/cloud/hetzner-mcp/cartridge.json
- `category` — required field missing
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/cloud/linode-mcp/cartridge.json
- `category` — required field missing
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/cloud/railway-mcp/cartridge.json
- `category` — required field missing
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/cloud/render-mcp/cartridge.json
- `category` — required field missing
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/code-quality/coderag-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/code-quality/sanctify-mcp/cartridge.json
- `category` — required field missing
- `protocols` — required field missing
- `api` — required field missing
- `auth.env_var` — required field missing
- `auth.credential_source` — required field missing
- `tools[0].inputSchema` — required field missing
- `tools[1].inputSchema` — required field missing
- `tools[2].inputSchema` — required field missing
- `tools[3].inputSchema` — required field missing
- `tools[4].inputSchema` — required field missing

### cartridges/domains/communications/burble-admin-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/communications/comms-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/communications/discord-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/communications/matrix-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/communications/notifyhub-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/communications/slack-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/communications/telegram-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/community/civic-connect-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/community/feedback-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/config/conflow-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/config/k9iser-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/container/container-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/container/docker-hub-mcp/cartridge.json
- `category` — required field missing
- `auth.method` — value "bearer" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/container/k8s-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/container/stapeln-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/database/arango-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/database/clickhouse-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/database/database-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/database/duckdb-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/database/mongodb-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/database/neo4j-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/database/neon-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/database/postgresql-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/database/redis-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/database/supabase-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/database/turso-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/database/verisimdb-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/development/codeseeker-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/development/fireflag-mcp/cartridge.json
- `category` — required field missing
- `protocols` — required field missing
- `api` — required field missing
- `auth.env_var` — required field missing
- `auth.credential_source` — required field missing
- `tools[0].inputSchema` — required field missing
- `tools[1].inputSchema` — required field missing
- `tools[2].inputSchema` — required field missing
- `tools[3].inputSchema` — required field missing
- `tools[4].inputSchema` — required field missing

### cartridges/domains/development/git-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/development/github-api-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/development/gitlab-api-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/education/kategoria-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/formal-verification/echidna-llm-mcp/cartridge.json
- `category` — required field missing
- `auth.method` — value "api_key_header" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/formal-verification/ephapax-mcp/cartridge.json
- `category` — required field missing
- `protocols` — required field missing
- `api` — required field missing
- `auth.env_var` — required field missing
- `auth.credential_source` — required field missing
- `tools[0].inputSchema` — required field missing
- `tools[1].inputSchema` — required field missing
- `tools[2].inputSchema` — required field missing
- `tools[3].inputSchema` — required field missing
- `tools[4].inputSchema` — required field missing

### cartridges/domains/formal-verification/proof-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/gaming/game-admin-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/gaming/idaptik-admin-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/gaming/npc-mcp/cartridge.json
- `category` — required field missing
- `api` — required field missing
- `auth.env_var` — required field missing
- `auth.credential_source` — required field missing

### cartridges/domains/gaming/ums-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/infrastructure/aerie-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/infrastructure/hesiod-mcp/cartridge.json
- `category` — required field missing
- `protocols` — required field missing
- `api` — required field missing
- `auth.env_var` — required field missing
- `auth.credential_source` — required field missing

### cartridges/domains/infrastructure/iac-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/knowledge/librarian-mcp/cartridge.json
- `category` — required field missing
- `api` — required field missing
- `auth.env_var` — required field missing
- `auth.credential_source` — required field missing

### cartridges/domains/knowledge/local-memory-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/knowledge/obsidian-mcp/cartridge.json
- `category` — required field missing
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/languages/007-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/languages/affinescript-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/languages/lang-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/languages/lsp-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/languages/orchestrator-lsp-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/languages/toolchain-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/languages/typed-wasm-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/legal/pmpl-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/messaging/queues-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/multimodal/elevenlabs-mcp/cartridge.json
- `category` — required field missing
- `auth.method` — value "api_key" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/multimodal/ffmpeg-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/multimodal/replicate-mcp/cartridge.json
- `category` — required field missing
- `auth.method` — value "api_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/multimodal/whisper-mcp/cartridge.json
- `category` — required field missing
- `auth.method` — value "optional_api_key" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/observability/grafana-mcp/cartridge.json
- `category` — required field missing
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/observability/observe-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/observability/prometheus-mcp/cartridge.json
- `category` — required field missing
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/observability/sentry-mcp/cartridge.json
- `category` — required field missing
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/open-data/opendatamcp/cartridge.json
- `category` — required field missing
- `name` — value "opendatamcp" does not match pattern /^[a-z0-9]+(-[a-z0-9]+)*-(mcp|lsp|dap|bsp|debug|format|lint|build|nesy|agentic|fleet)$/

### cartridges/domains/productivity/airtable-mcp/cartridge.json
- `category` — required field missing
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/productivity/google-docs-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/productivity/google-sheets-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/productivity/notion-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/productivity/todoist-mcp/cartridge.json
- `category` — required field missing
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/project-management/jira-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/project-management/linear-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/registry/crates-mcp/cartridge.json
- `category` — required field missing
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/registry/hackage-mcp/cartridge.json
- `category` — required field missing
- `auth.method` — value "basic" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/registry/hex-mcp/cartridge.json
- `category` — required field missing
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/registry/npm-registry-mcp/cartridge.json
- `category` — required field missing
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/registry/opam-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/registry/opsm-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/registry/pypi-mcp/cartridge.json
- `category` — required field missing
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/repository-management/reposystem-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/research/academic-workflow-mcp/cartridge.json
- `category` — required field missing
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
- `category` — required field missing
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

### cartridges/domains/research/research-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/research/search-mcp/cartridge.json
- `category` — required field missing
- `auth.method` — value "api_key" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/research/zotero-mcp/cartridge.json
- `category` — required field missing
- `auth.method` — value "bearer_token" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/security/dns-shield-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/security/panic-attack-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/security/rokur-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/security/secrets-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/security/vault-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/security/vext-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/security/vordr-mcp/cartridge.json
- `category` — required field missing

### cartridges/domains/vector/chromadb-mcp/cartridge.json
- `category` — required field missing
- `auth.method` — value "optional_bearer" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/vector/pinecone-mcp/cartridge.json
- `category` — required field missing
- `auth.method` — value "api_key" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/vector/qdrant-mcp/cartridge.json
- `category` — required field missing
- `auth.method` — value "api_key" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/vector/weaviate-mcp/cartridge.json
- `category` — required field missing
- `auth.method` — value "api_key" not in enum ["none","api-key","oauth2","vault"]

### cartridges/domains/web/ssg-mcp/cartridge.json
- `category` — required field missing

### cartridges/templates/gossamer-mcp/cartridge.json
- `category` — required field missing
