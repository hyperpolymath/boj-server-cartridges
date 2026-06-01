# poly-orchestrator-lsp

**Orchestration layer for 12 hyperpolymath LSP servers with stapeln integration**

[![License](https://img.shields.io/badge/license-MPL--2.0-brightgreen.svg)](./LICENSE)
[![Elixir](https://img.shields.io/badge/elixir-1.17+-purple.svg)](https://elixir-lang.org/)
[![OTP](https://img.shields.io/badge/OTP-27+-red.svg)](https://www.erlang.org/)
[![Tests](https://img.shields.io/badge/tests-47%2F47%20passing-brightgreen.svg)](#)
[![Extension](https://img.shields.io/badge/VSCode-ReScript-blue.svg)](./vscode-extension)

## Overview

poly-orchestrator-lsp is the 13th LSP server in the hyperpolymath ecosystem, providing **orchestration and coordination** for the other 12 domain-specific LSP servers. It enables **automated stack deployment** by parsing `stack.compose.toml` files and executing multi-service workflows.

## Architecture

```
┌─────────────────────────────────────┐
│  stapeln (Visual Layer)             │
│  - Drag-and-drop stack designer     │
│  - miniKanren security reasoning    │
│  - Exports stack.compose.toml       │
└──────────────┬──────────────────────┘
               │
               │ stack.compose.toml
               ↓
┌─────────────────────────────────────┐
│  poly-orchestrator-lsp (This!)      │
│  - Parse and validate stacks        │
│  - Build dependency graphs          │
│  - Orchestrate 12 LSP servers       │
│  - Handle rollbacks                 │
└──────────────┬──────────────────────┘
               │
               │ LSP Protocol
               ↓
┌─────────────────────────────────────┐
│  12 Domain-Specific LSP Servers     │
│  poly-cloud, poly-db, poly-k8s...   │
└─────────────────────────────────────┘
```

## Features

- ✅ **Stack Orchestration** - Execute multi-component deployments
- ✅ **Dependency Resolution** - Automatic topological sorting
- ✅ **Parallel Execution** - Run independent components concurrently
- ✅ **LSP-to-LSP Communication** - Coordinate 12 LSP servers
- ✅ **Rollback Support** - Cascade rollback on failure
- ✅ **Security Validation** - miniKanren policy enforcement
- ✅ **VeriSimDB Integration** - Shared orchestration history
- ✅ **LSP Features** - Completion, diagnostics, hover for stack files
- ✅ **Progress Tracking** - Real-time execution status
- ✅ **Verification** - Post-deployment health checks

## Supported Component Types

| Type | LSP Server | Examples |
|------|-----------|----------|
| `cloud.*` | poly-cloud-lsp | Provision VPC, subnets |
| `database.*` | poly-db-lsp | PostgreSQL, MongoDB, Redis |
| `container.*` | poly-container-lsp | Build images |
| `kubernetes.*` | poly-k8s-lsp | Deploy to K8s |
| `observability.*` | poly-observability-lsp | Prometheus, Grafana |
| `secrets.*` | poly-secret-lsp | Vault, SOPS |
| `git.*` | poly-git-lsp | Create repos |
| `queue.*` | poly-queue-lsp | RabbitMQ, NATS |
| `ssg.*` | poly-ssg-lsp | Static site generation |
| `iac.*` | poly-iac-lsp | OpenTofu, Pulumi |
| `browser.*` | claude-firefox-lsp | Browser automation |
| `proof.*` | poly-proof-lsp | Formal verification |

## Installation

### Server

```bash
git clone https://github.com/hyperpolymath/poly-orchestrator-lsp.git
cd poly-orchestrator-lsp
mix deps.get
mix compile
mix test  # 47 tests, 0 failures
```

### VSCode Extension

**From Marketplace** (once published):
```bash
code --install-extension hyperpolymath.poly-orchestrator-lsp
```

**From Local Build**:
```bash
cd vscode-extension
npm install && npm run build
./node_modules/.bin/vsce package
code --install-extension poly-orchestrator-lsp-0.1.0.vsix
```

**Extension Features**:
- ✅ Auto-completion for component types and LSP servers
- ✅ Real-time diagnostics (validation, cycles, security)
- ✅ Hover documentation with duration estimates
- ✅ Commands: Execute Stack, Validate, Estimate Duration, Restart Server
- ✅ Built with **ReScript** (type-safe, 195ms compile time)
- ✅ Icon: Custom orchestration visualization

**Quick Start**: See [QUICKSTART.md](QUICKSTART.md) for 60-second setup guide.

## Usage

### 1. Create a Stack File

Create `my-stack.compose.toml`:

```toml
[metadata]
version = "1.0.0"
name = "my-web-stack"

[[components]]
id = "cloud-infrastructure"
type = "cloud.provision"
lsp_server = "poly-cloud"
phase = 1

[components.config]
provider = "aws"
region = "us-west-2"

[[components]]
id = "postgres-db"
type = "database.provision"
lsp_server = "poly-db"
phase = 2
depends_on = ["cloud-infrastructure"]

[components.config]
engine = "postgresql"
version = "16"
```

### 2. Execute the Stack

```elixir
# Parse stack
{:ok, stack} = PolyOrchestrator.Orchestrator.StackParser.parse_file("my-stack.compose.toml")

# Build execution plan
{:ok, plan} = PolyOrchestrator.Orchestrator.Planner.build_plan(stack)

# Execute
{:ok, result} = PolyOrchestrator.Orchestrator.Executor.execute(plan)
```

### 3. Use in VSCode

The LSP server provides:
- **Completion**: Component types, LSP server names
- **Diagnostics**: Validation errors, dependency cycles
- **Hover**: Documentation for components
- **Commands**: Execute stack, validate, rollback

## Integration with stapeln

poly-orchestrator-lsp consumes `stack.compose.toml` files exported from [stapeln](https://github.com/hyperpolymath/stapeln), the visual container stack designer.

**Flow**:
1. Design stack visually in stapeln
2. stapeln exports `stack.compose.toml` with security policies
3. poly-orchestrator-lsp executes the stack
4. Results stored in VeriSimDB for both systems

## VeriSimDB Integration

poly-orchestrator stores orchestration history in stapeln's VeriSimDB:

- **Graph**: Dependency relationships
- **Vector**: Semantic search for similar stacks
- **Document**: Full stack.compose.toml files
- **Temporal**: Deployment timeline
- **Semantic**: Metadata and tags

```elixir
# Query past deployments
{:ok, history} = PolyOrchestrator.VeriSimDB.Client.query_history(%{
  stack_id: "my-web-stack",
  time_range: {start_time, end_time}
})

# Find similar stacks
{:ok, similar} = PolyOrchestrator.VeriSimDB.Client.find_similar_stacks(
  "e-commerce stack with PostgreSQL"
)
```

## Development

```bash
# Run tests
mix test

# Quality checks
mix quality

# Start interactive shell
iex -S mix
```

## Requirements

- Elixir 1.17+
- Erlang/OTP 27+
- All 12 hyperpolymath LSP servers installed

## Related Projects

- [stapeln](https://github.com/hyperpolymath/stapeln) - Visual stack designer
- [poly-cloud-lsp](https://github.com/hyperpolymath/poly-cloud-lsp) - Cloud infrastructure
- [poly-db-lsp](https://github.com/hyperpolymath/poly-db-lsp) - Database management
- [poly-k8s-lsp](https://github.com/hyperpolymath/poly-k8s-lsp) - Kubernetes orchestration
- [See all 12 LSP servers](https://github.com/hyperpolymath/poly-ssg-lsp/blob/main/LSP-SERVERS-INDEX.md)

## License

MPL-2.0 (Mozilla Public License 2.0)

## Authors

- **Jonathan D.A. Jewell** <j.d.a.jewell@open.ac.uk>
- **Co-Authored-By**: Claude Sonnet 4.5 <noreply@anthropic.com>

---

**Part of the [hyperpolymath](https://github.com/hyperpolymath) ecosystem**
