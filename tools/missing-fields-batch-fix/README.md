<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath) -->

# missing-fields-batch-fix

One-shot tool used to close the mechanical subset of issue #20. The
canonical schema requires several top-level + nested fields that some
"minimal" cartridge manifests omit. This script fills them with safe,
schema-conformant defaults:

| Field | Default |
|---|---|
| `protocols` | Inferred from the role suffix in `name` (`-mcp` → `["MCP"]`, `-lsp` → `["LSP"]`, …). |
| `api` | `{ "base_url": "local://<name>", "content_type": "application/json" }` |
| `auth.env_var` | `null` |
| `auth.credential_source` | `null` |
| `tools[*].inputSchema` | `{ "type": "object", "properties": {} }` |

Unlike the category/auth scripts, this one re-serialises each touched
manifest in canonical 2-space form with schema-ordered properties. The
manifests that needed patching were all single-line / heavily compact —
restructuring them to the gossamer-template shape is a wash for human
reading and makes downstream diffs comprehensible.

The three name-pattern stragglers (`boj-health`, `origenemcp`,
`opendatamcp`) are **skipped**: renaming a cartridge changes its
identity downstream and needs owner direction.

## Usage

```bash
cd tools/missing-fields-batch-fix
deno run --allow-read --allow-write main.ts
```

The script is idempotent: manifests already carrying every required
field are counted under `alreadyComplete` and skipped.

After running, validate with:

```bash
cd ../validate-cartridges
deno task audit
```
