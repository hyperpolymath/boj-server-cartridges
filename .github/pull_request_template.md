<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath) -->

## Summary

<!-- One or two lines: what the PR changes and why. -->

## Schema-validation note

<!-- Mark the box that applies. -->

- [ ] This PR adds or modifies one or more `cartridge.json` manifests.
- [ ] This PR does not touch any `cartridge.json`.

If a manifest was touched: confirm `cd tools/validate-cartridges && deno task audit` came back clean locally.
The strict-mode CI gate at [`.github/workflows/cartridge-schema.yml`](../.github/workflows/cartridge-schema.yml) will also enforce this on push; the documented baseline is in [`audits/cartridge-schema-2026-06-01.md`](../audits/cartridge-schema-2026-06-01.md).

If the PR bumps [`schemas/PINNED-SHA`](../schemas/PINNED-SHA): name the upstream `hyperpolymath/standards` commit and follow the mirror discipline in [`schemas/SCHEMA-MIRROR.md`](../schemas/SCHEMA-MIRROR.md).

## Refs

<!-- Link related issues / upstream PRs / boj-server consumer issues. e.g. boj-server#183, standards#... -->
