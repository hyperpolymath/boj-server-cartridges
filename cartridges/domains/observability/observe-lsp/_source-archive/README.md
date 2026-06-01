# poly-observability-lsp

> Language Server Protocol implementation for observability tools (Prometheus, Grafana, Loki, Jaeger)

[![License: MPL-2.0](https://img.shields.io/badge/License-MPL--2.0-brightgreen.svg)](https://www.mozilla.org/en-US/MPL/2.0/)
[![Elixir 1.17+](https://img.shields.io/badge/elixir-1.17+-purple.svg)](https://elixir-lang.org/)

## Overview

**poly-observability-lsp** provides IDE integration for observability tools across the cloud-native ecosystem. Built with Elixir's BEAM VM, each tool adapter runs as an isolated process with automatic fault recovery.

## Supported Tools

- **Prometheus** - Monitoring and alerting with PromQL query language
- **Grafana** - Observability dashboards and visualization
- **Loki** - Log aggregation with LogQL query language
- **Jaeger** - Distributed tracing for microservices

## Features

- 🔄 **Auto-detection**: Detects observability tools from project files
- 🔍 **Query validation**: Validate PromQL and LogQL queries before execution
- 📊 **Dashboard integration**: List and validate Grafana dashboards
- 🚨 **Alert monitoring**: Check alert status and configuration
- ⚡ **Commands**: Execute queries directly from editor
- 🛡️ **Fault isolation**: Crash in one adapter doesn't affect others

## Installation

```bash
git clone https://github.com/hyperpolymath/poly-observability-lsp
cd poly-observability-lsp
mix deps.get
mix compile
```

## Required CLI Tools

Each adapter requires its corresponding CLI tool to be installed:

- **Prometheus**: `promtool` (from Prometheus installation)
- **Grafana**: `grafana-cli` (from Grafana installation)
- **Loki**: `logcli` (from Loki installation)
- **Jaeger**: `jaeger-query` (from Jaeger installation)

## Usage

### Start the LSP Server

```bash
just start
```

### VSCode Extension

See `vscode-extension/` directory for the VSCode extension that uses this LSP server.

## Configuration

Each observability tool is detected based on its configuration files:

| Tool | Config Files |
|------|--------------|
| Prometheus | `prometheus.yml` |
| Grafana | `grafana.ini`, `grafana/` directory |
| Loki | `loki.yaml`, `loki-config.yaml` |
| Jaeger | `jaeger-config.yml`, `docker-compose.yml` (with Jaeger) |

## Architecture

Each adapter implements the `PolyObservability.Adapters.Behaviour`:

- `detect/1` - Detect if tool is present in project
- `query_metrics/3` - Query metrics (Prometheus)
- `query_logs/3` - Query logs (Loki)
- `query_traces/3` - Query traces (Jaeger)
- `list_dashboards/1` - List dashboards (Grafana)
- `alert_status/1` - Get alert status
- `version/0` - Get tool version
- `metadata/0` - Get tool metadata

## Development

```bash
# Install dependencies
just deps

# Run tests
just test

# Run quality checks
just quality

# Start REPL
just repl
```

## License

MPL-2.0
