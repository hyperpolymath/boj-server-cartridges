---
name: Bug report
about: Report a bug in a cartridge, the schema mirror, or the Deno validator
title: 'bug: '
labels: bug
assignees: hyperpolymath

---

<!-- SPDX-License-Identifier: MPL-2.0 -->
<!-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath) -->

## Cartridge

If the bug is in a specific cartridge, name it (e.g. `gossamer-mcp`, `database-lsp`). Otherwise put `n/a — registry-side` (schema mirror, validator, CI gate, taxonomy, audits/).

## Reproduction

Steps to reproduce. For schema-validation bugs, paste the exact `cd tools/validate-cartridges && deno task audit-verbose` invocation and its output.

## Expected vs actual

What you expected to happen, and what actually happened.

## Schema-validator output (if relevant)

```
<paste output of `deno task audit-verbose` for the affected cartridge>
```

## Environment

- Deno version (validator-side): `deno --version`
- Host (if reproducing through a downstream consumer, e.g. `boj-server`): version + commit.

## Notes

Cross-link related upstream issues if applicable: cartridge spec lives at [hyperpolymath/standards](https://github.com/hyperpolymath/standards) `cartridges/`; the host-runtime + fetcher contract live at [hyperpolymath/boj-server](https://github.com/hyperpolymath/boj-server) (`boj-server#183`).
