<!-- SPDX-License-Identifier: MPL-2.0 -->
<!-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath) -->

# category-batch-fix

One-shot tool used to close issue #18 — the canonical schema requires a
top-level `category` field on every cartridge manifest, but the migration
that seeded this repo from `boj-server/cartridges/` did not add the field.
This script walked all 139 manifests, derived `category` from the file's
path (`domains/` → `"domain"`, `cross-cutting/` → `"cross-cutting"`,
`templates/` → `"template"`), and inserted the field via string-level
patching (preserving the rest of each manifest's formatting).

Kept in-tree as a precedent for similar mechanical batch fixes (e.g.
future enum-mapping or missing-field campaigns under #19 / #20).

## Usage

```bash
cd tools/category-batch-fix
deno run --allow-read --allow-write main.ts
```

The script is idempotent: manifests that already have `category` are
counted under `alreadyHad` and skipped. After running, validate with:

```bash
cd ../validate-cartridges
deno task audit
```
