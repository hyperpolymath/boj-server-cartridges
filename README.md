[![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-pink?logo=github)](https://github.com/sponsors/hyperpolymath)
[![License: MPL 2.0](https://img.shields.io/badge/License-MPL_2.0-brightgreen.svg)](./LICENSE)

<!-- SPDX-License-Identifier: MPL-2.0 -->
<!-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath) -->

# boj-server-cartridges

Canonical home of **BoJ cartridges**. Hosts (`boj-server`, `panll`, others) fetch cartridges from here on demand into a host-local cache; this repository ships the source tree.

Machine-readable summary: [`0.1-AI-MANIFEST.a2ml`](0.1-AI-MANIFEST.a2ml).

## Status

🟢 **v0.1 — schema-validation foundation landed 2026-06-01.** Initial migration of cartridges from `boj-server/cartridges/` (snapshot 2026-05-26) is complete; Boj-server's catalog refactor to fetch from here has merged. Schema validator + CI gate are live in audit mode; a drift inventory has been captured (139 manifests, 12 passing, 127 failing — see [`audits/cartridge-schema-2026-06-01.md`](audits/cartridge-schema-2026-06-01.md)). Remediation is tracked under #18 / #19 / #20.

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

`schemas/cartridge-v1.json` mirrors the canonical spec at [hyperpolymath/standards](https://github.com/hyperpolymath/standards/blob/main/cartridges/cartridge-v1.json). The mirror is SHA-pinned via [`schemas/PINNED-SHA`](schemas/PINNED-SHA) (see also [schemas/SCHEMA-MIRROR.md](schemas/SCHEMA-MIRROR.md)).

## Validation

The pinned mirror is verified against `schemas/PINNED-SHA` on every CI run, then every `cartridge.json` is checked against `schemas/cartridge-v1.json` by the in-tree Deno validator under [`tools/validate-cartridges/`](tools/validate-cartridges/):

| Task | Behaviour |
|---|---|
| `deno task audit` | Walks all manifests, prints a one-line summary per cartridge; exit 0 regardless. |
| `deno task audit-verbose` | As `audit`, but expands every schema violation per cartridge. |
| `deno task strict` | Fails the run on any violation. Used once the drift inventory is closed. |

CI ([`.github/workflows/cartridge-schema.yml`](.github/workflows/cartridge-schema.yml)) runs the validator in `audit` mode today and will flip to `strict` once the drift inventory is closed. The current drift baseline lives at [`audits/cartridge-schema-2026-06-01.md`](audits/cartridge-schema-2026-06-01.md); recurring fixes are tracked under #18 (missing `category`), #19 (`auth.method` enum mismatches: `bearer_token` and `api_key` vs canonical `api-key`), and #20 (canonical-only cartridges + other missing top-level fields).

Canonical schema home: [hyperpolymath/standards](https://github.com/hyperpolymath/standards/tree/main/cartridges).

## Versioning + on-demand fetch

Each cartridge directory contains its own `cartridge.json` with `version` (semver). Hosts fetch cartridges by name + version; the tray UI (`hyperpolymath/boj-server`) exposes "Add cartridge source" to point at this registry (the canonical default) or any other GitHub URL.

## Inventory

- **139 cartridges** total; 14 are canonical-only (not yet wired into a host runtime — see #20).
- **30 functional domains** + **6 cross-cutting categories** + **1 template**.
- All cartridges retain their original `cartridge.json` manifests; the `category` field is being backfilled under #18.

## Contributing

1. Use the **gossamer-mcp** template as your starting point: `cp -r cartridges/templates/gossamer-mcp cartridges/domains/<your-domain>/<your-cartridge-name>` (or use the minter tool once landed). The template itself will be updated to be schema-compliant as part of the drift remediation under #18.
2. Update the manifest to reflect your cartridge's name (role-suffixed), domain, protocols, tools.
3. New cartridges should validate cleanly against `schemas/cartridge-v1.json`: `cd tools/validate-cartridges && deno task audit`.
4. Open a PR; auto-merge is enabled by default for this repo.

## License

[MPL-2.0](LICENSE). Cartridges retain their individual SPDX identifiers per `cartridge.json`.
