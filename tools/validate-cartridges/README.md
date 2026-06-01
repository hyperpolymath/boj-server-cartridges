<!-- SPDX-License-Identifier: MPL-2.0 -->
<!-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath) -->

# validate-cartridges

Walks `cartridges/` and validates every `cartridge.json` against the canonical
schema at `schemas/cartridge-v1.json`. Zero-dependency Deno script
(`jsr:@std/fs` + `jsr:@std/path` only).

## Usage

```bash
cd tools/validate-cartridges
deno task audit            # summary report; exits 0 even on failure
deno task audit-verbose    # adds per-manifest failure list
deno task strict           # exits non-zero on any failure
```

## Modes

- `audit` (default) — print a summary + top recurring issues; exit 0. Use this
  during the drift-inventory phase (the report tells you what to fix).
- `strict` — exit non-zero if any manifest fails. Use this once drift is fixed
  and as a blocking CI gate.

## Why a hand-rolled validator

The schema is small and stable; pulling in a full JSON-Schema implementation
(ajv etc.) means npm or jsr-npm-shim plumbing that the estate npm→deno policy
asks us to avoid. This script covers the subset the schema actually uses:
`type`, `enum`, `pattern`, `required`, `properties`, `items`, `minItems`.

If the schema starts using `oneOf` / `anyOf` / `$ref`, swap in a fuller
implementation at that point.
