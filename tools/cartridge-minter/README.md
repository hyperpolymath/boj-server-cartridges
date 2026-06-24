<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Cartridge minter

Scaffolds a new BoJ cartridge from a `minter.toml` configuration.

Until this tool landed, new cartridges were created by `cp -r cartridges/templates/gossamer-mcp <new-name>` followed by manual edits of `cartridge.json`, `mod.js`, etc. — the Phase-3B completion record (in boj-server) documents that workflow. The minter replaces it with a single command.

## Usage

```sh
deno run --allow-read --allow-write tools/cartridge-minter/mint.ts <path/to/minter.toml> [--dest <override-path>]
```

If `--dest` is omitted, the destination is derived from `minter.toml`:

| `category` | Destination |
|---|---|
| `domain` (default) | `cartridges/domains/<normalised-domain>/<name>/` |
| `cross-cutting` | `cartridges/cross-cutting/<cross_cutting_category>/<name>/` |
| `template` | `cartridges/templates/<name>/` |

## `minter.toml` format

```toml
# Required
name = "linear-mcp"                    # must end in a canonical role suffix
description = "Linear project management cartridge"
version = "0.1.0"                      # semver
domain = "Comms"                       # will be normalised (see below)
protocols = ["MCP", "GraphQL"]
tier = "Ayo"                           # Teranga | Shield | Ayo

# Optional taxonomy hint
category = "domain"                    # domain | cross-cutting | template
cross_cutting_category = "agentic"     # required when category == "cross-cutting"

# Optional auth (string shorthand or table form both accepted)
auth = "bearer"                        # shorthand
# OR
[auth]
method = "bearer_token"
env_var = "LINEAR_API_KEY"
credential_source = "vault-mcp"

# Optional API metadata
[api]
base_url = "https://api.linear.app/graphql"
content_type = "application/json"
```

## Validation

Before scaffolding, the minter validates:

- `name` ends in a canonical role suffix `(-mcp|-lsp|-dap|-bsp|-debug|-format|-lint|-build|-nesy|-agentic|-fleet)`
- `version` is valid semver
- `tier` is one of `Teranga | Shield | Ayo`
- All required fields present

## Domain normalisation

Mixed-case / synonym domains in input are mapped to canonical kebab-case:
`Cloud` → `cloud`, `CI/CD` → `ci-cd`, `Container Orchestration` → `container`,
`Package Management` → `registry`, etc. See the `DOMAIN_NORMALISE` map in `mint.ts`.

## Post-mint workflow

The minter:

1. Copies `cartridges/templates/gossamer-mcp/` to the destination.
2. Overwrites `cartridge.json` with a manifest derived from `minter.toml`, conforming to the [canonical schema](../../schemas/cartridge-v1.json) (`$schema` set to `https://hyperpolymath.dev/standards/cartridges/cartridge-v1.json`).
3. Drops the original `minter.toml` into the new cartridge dir for re-mint reproducibility.

You then edit:

- `cartridge.json` — add your `tools[]` array.
- `mod.js` — implement the host entry point (calls your loopback backend).
- `adapter/` — the Deno-side MCP server (or LSP/DAP/BSP server per role).
- `ffi/` — Zig FFI bindings to native libraries.
- `abi/` — Idris2 ABI definitions (REQUIRED for Teranga / Shield tier).
- `README.adoc` — human-facing docs.

## Example

```sh
$ cat > /tmp/example-minter.toml <<EOF
name = "example-mcp"
description = "Example demo cartridge"
version = "0.1.0"
domain = "Productivity"
protocols = ["MCP", "REST"]
tier = "Ayo"
EOF

$ deno run --allow-read --allow-write tools/cartridge-minter/mint.ts /tmp/example-minter.toml
✓ Minted example-mcp → cartridges/domains/productivity/example-mcp
  Edit cartridge.json to declare your tools array.
  Edit mod.js / adapter/ / ffi/ / abi/ as your implementation requires.
```
