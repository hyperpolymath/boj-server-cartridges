<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath) -->

# Cartridge schema mirror

The file `cartridge-v1.json` in this directory is a **SHA-pinned mirror** of the canonical schema living at:

- **Canonical home:** [`hyperpolymath/standards`](https://github.com/hyperpolymath/standards/blob/main/cartridges/cartridge-v1.json)
- **Canonical URL:** `https://hyperpolymath.dev/standards/cartridges/cartridge-v1.json`
- **Pinned commit:** `f5f0506a6ec88e574753eee701a268e0d4b3a7f2` (set 2026-07-01 via hyperpolymath/standards#373; tracked via [PINNED-SHA](PINNED-SHA))
- **Pinned SHA-256 of file:** `7d03f79f9c881784eba21670ac86130371d02f54483b373c8673587c49ab8d08` (recorded in [PINNED-SHA](PINNED-SHA); enforced by `.github/workflows/cartridge-schema.yml`)

## Why mirror

Two reasons:

1. **Offline validation.** Hosts (boj-server, panll) and cartridge authors need to validate `cartridge.json` without round-tripping to a network resource.
2. **Reproducibility.** A given snapshot of this repository must validate against a deterministic schema version, so CI / fetchers must read the bundled copy, not the canonical URL.

## Refresh discipline

When the canonical schema in `hyperpolymath/standards` advances:

1. Open a PR here that updates `cartridge-v1.json` to the new content.
2. Update `PINNED-SHA` with the new commit SHA in standards and the new SHA-256 of the file.
3. The PR's description references the standards PR/commit that introduced the change.
4. Auto-merge once CI validates that all 125 cartridge manifests still parse against the new schema.

## What if they disagree?

Standards wins. Local mirror is always advancing toward standards. Cartridges authored against an older mirror remain valid as long as the schema change is backwards-compatible (the canonical schema is versioned; breaking changes ship as `cartridge-v2.json`).
