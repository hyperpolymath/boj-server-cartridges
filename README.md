[![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-pink?logo=github)](https://github.com/sponsors/hyperpolymath)

<!-- SPDX-License-Identifier: MPL-2.0 -->
<!-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath) -->

# boj-server-cartridges

Canonical home of **BoJ cartridges**. Hosts (`boj-server`, `panll`, others) fetch cartridges from here on demand into a host-local cache; this repository ships the source tree.

## Status

🟢 **v0.1 — populated from boj-server 2026-05-26.** Initial migration of 125 cartridges out of `boj-server/cartridges/` into this dedicated repository. Boj-server's catalog refactor to fetch from here is tracked separately.

## What is a cartridge?

See the canonical spec: [standards/cartridges/CARTRIDGE-FORMAT.adoc](https://github.com/hyperpolymath/standards/blob/main/cartridges/CARTRIDGE-FORMAT.adoc) and JSON schema: [cartridge-v1.json](https://github.com/hyperpolymath/standards/blob/main/cartridges/cartridge-v1.json).

A cartridge is a self-contained server unit consumed by a host to extend its tool surface (MCP), language-server reach (LSP), debug-adapter capabilities (DAP), build-tool integration (BSP), or other server-role mode. Cartridges are process-isolated (each backend listens on its own loopback port) and content-addressable.

## Taxonomy

Hybrid layout ratified in [docs/decisions/ADR-001-taxonomy.adoc](docs/decisions/ADR-001-taxonomy.adoc):

```
cartridges/
├── domains/                  ← cartridges grouped by functional domain
│   ├── cloud/                ← 10 cartridges (umbrella + 9 providers)
│   ├── database/             ← 12 cartridges (umbrella + 11 providers)
│   ├── ci-cd/, languages/, security/, research/, …  (30 domains total)
├── cross-cutting/            ← cartridges not bound to a single domain
│   ├── agentic/              ← agent-mcp, claude-ai-mcp, model-router-mcp, …
│   ├── nesy/                 ← nesy-mcp, ml-mcp
│   ├── build/                ← bsp-mcp (generic BSP server)
│   ├── debug/                ← dap-mcp (generic DAP server)
│   ├── fleet/                ← fleet-mcp (orchestration)
│   └── health/               ← boj-health
└── templates/                ← canonical scaffolds for new cartridges
    └── gossamer-mcp/         ← reference template
```

## Cartridge roles

A cartridge name ends in a canonical role suffix:

| Suffix | Role |
|---|---|
| `-mcp` | Model Context Protocol |
| `-lsp` | Language Server Protocol |
| `-dap` | Debug Adapter Protocol |
| `-bsp` | Build Server Protocol |
| `-debug` | Debugger (when not strictly DAP) |
| `-format` | Code formatter |
| `-lint` | Linter / static analyser |
| `-build` | Build orchestration |
| `-nesy` | Neurosymbolic reasoning |
| `-agentic` | Agent harness |
| `-fleet` | Fleet orchestrator |

A single domain may have multiple cartridges across roles, e.g. `database-mcp` + `database-lsp` + `database-format`.

## Schema

`schemas/cartridge-v1.json` mirrors the canonical spec at [hyperpolymath/standards](https://github.com/hyperpolymath/standards/blob/main/cartridges/cartridge-v1.json). The mirror is SHA-pinned via [schemas/SCHEMA-MIRROR.md](schemas/SCHEMA-MIRROR.md).

## Versioning + on-demand fetch

Each cartridge directory contains its own `cartridge.json` with `version` (semver). Hosts fetch cartridges by name + version; the tray UI (`hyperpolymath/boj-server`) exposes "Add cartridge source" to point at this registry (the canonical default) or any other GitHub URL.

## Inventory (this initial commit)

- **125 cartridges** copied from `boj-server/cartridges/` (snapshot 2026-05-26).
- **30 functional domains** + **6 cross-cutting categories** + **1 template**.
- All cartridges retain their original `cartridge.json` manifests. A separate follow-up PR will add the new required `category` field to each manifest.

## Contributing

1. Use the **gossamer-mcp** template as your starting point: `cp -r cartridges/templates/gossamer-mcp cartridges/domains/<your-domain>/<your-cartridge-name>` (or use the minter tool once landed).
2. Update the manifest to reflect your cartridge's name (role-suffixed), domain, protocols, tools.
3. Open a PR; auto-merge is enabled by default for this repo.

## License

[MPL-2.0](LICENSE). Cartridges retain their individual SPDX identifiers per `cartridge.json`.
