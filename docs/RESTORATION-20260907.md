# Runtime restoration, 7 September 2026

The original server and this registry remain the active implementation.
`metadatastician/boj-server-mk2` is archived. The replacement architecture did
not justify abandoning the implemented native and OTP components.

Active sources had been converted into syntax rejected by AffineScript 0.1.1.
Working predecessors were recovered from Git and ported to Bun JavaScript,
or restored as ReScript for the VS Code extension. Five SDK adapters were
unwired placeholders with invented results; they are retired with explicit
unavailability instead of being represented as working integrations.

| Previous source | Predecessor at parent of | Disposition |
|---|---|---|
| `cartridges/cross-cutting/orchestration/stack-orchestrator-mcp/adapter/executor.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |
| `cartridges/cross-cutting/orchestration/stack-orchestrator-mcp/adapter/executor_test.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |
| `cartridges/cross-cutting/orchestration/stack-orchestrator-mcp/adapter/integration_test.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |
| `cartridges/cross-cutting/orchestration/stack-orchestrator-mcp/adapter/lsp_client.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |
| `cartridges/cross-cutting/orchestration/stack-orchestrator-mcp/adapter/lsp_client_test.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |
| `cartridges/cross-cutting/orchestration/stack-orchestrator-mcp/adapter/parser.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |
| `cartridges/cross-cutting/orchestration/stack-orchestrator-mcp/adapter/parser_test.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |
| `cartridges/cross-cutting/orchestration/stack-orchestrator-mcp/adapter/planner.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |
| `cartridges/cross-cutting/orchestration/stack-orchestrator-mcp/adapter/planner_test.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |
| `cartridges/cross-cutting/orchestration/stack-orchestrator-mcp/adapter/rollback.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |
| `cartridges/cross-cutting/orchestration/stack-orchestrator-mcp/adapter/rollback_test.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |
| `cartridges/cross-cutting/orchestration/stack-orchestrator-mcp/adapter/types.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |
| `cartridges/domains/code-quality/sanctify-mcp/adapter/mod.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Retired: unwired SDK placeholder |
| `cartridges/domains/development/fireflag-mcp/adapter/mod.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Retired: unwired SDK placeholder |
| `cartridges/domains/formal-verification/proof-lsp/adapter/backends/agda.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |
| `cartridges/domains/formal-verification/proof-lsp/adapter/backends/base.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |
| `cartridges/domains/formal-verification/proof-lsp/adapter/backends/coq.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |
| `cartridges/domains/formal-verification/proof-lsp/adapter/backends/isabelle.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |
| `cartridges/domains/formal-verification/proof-lsp/adapter/backends/lean.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |
| `cartridges/domains/formal-verification/proof-lsp/adapter/backends/registry.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |
| `cartridges/domains/formal-verification/proof-lsp/adapter/backends_test.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |
| `cartridges/domains/formal-verification/proof-lsp/adapter/handlers/completion.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |
| `cartridges/domains/formal-verification/proof-lsp/adapter/handlers/diagnostic.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |
| `cartridges/domains/formal-verification/proof-lsp/adapter/handlers/executeCommand.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |
| `cartridges/domains/formal-verification/proof-lsp/adapter/handlers/hover.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |
| `cartridges/domains/formal-verification/proof-lsp/adapter/handlers/initialize.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |
| `cartridges/domains/formal-verification/proof-lsp/adapter/integration_test.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |
| `cartridges/domains/formal-verification/proof-lsp/adapter/server.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |
| `cartridges/domains/formal-verification/proof-lsp/adapter/server_test.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |
| `cartridges/domains/formal-verification/proof-lsp/adapter/types.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |
| `cartridges/domains/infrastructure/hesiod-mcp/adapter/mod.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Retired: unwired SDK placeholder |
| `cartridges/domains/languages/orchestrator-lsp-mcp/panels/src/Extension.affine` | `45110482be602e81f18962436b3456809ead6104` | Restored and ported |
| `cartridges/domains/languages/orchestrator-lsp-mcp/panels/src/LanguageClient.affine` | `45110482be602e81f18962436b3456809ead6104` | Restored and ported |
| `cartridges/domains/languages/orchestrator-lsp-mcp/panels/src/VscodeApi.affine` | `45110482be602e81f18962436b3456809ead6104` | Restored and ported |
| `cartridges/domains/research/academic-workflow-mcp/adapter/mod.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Retired: unwired SDK placeholder |
| `cartridges/domains/research/bofig-mcp/adapter/mod.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Retired: unwired SDK placeholder |
| `tools/auth-method-batch-fix/main.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |
| `tools/build-catalog/main.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |
| `tools/cartridge-minter/mint.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |
| `tools/category-batch-fix/main.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |
| `tools/missing-fields-batch-fix/main.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |
| `tools/validate-cartridges/main.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |
| `tools/validate-cartridges/main_test.affine` | `a528374aa4e509dabbfc1c34a6a6a824714d3146` | Restored and ported |

The shared process helper is part of the cartridge tree and must accompany
adapters on installation. Install the registry as a coherent snapshot.

LSP command failure is separate from successful JSON-RPC transport. Connections
serialize requests, match response IDs, bound buffered output and kill their
child on deadline. A deadline after dispatch leaves the external outcome
unknown; a compensating operation cannot undo an already disclosed result.

Interactive proof goals, tactic application and theorem search now return
explicit unsupported errors. Recovered code is not evidence that these
operations were implemented. The VS Code extension compiles; activation is checked against a mock VS Code host, not a running GUI editor.
