<!-- SPDX-License-Identifier: MPL-2.0 -->
<!-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath) -->

# Changelog

All notable changes to `boj-server-cartridges` are recorded here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — 2026-06-01

### Added

- Initial population from `boj-server/cartridges/` (snapshot 2026-05-26): 125 cartridges migrated into the taxonomied layout under [`cartridges/`](cartridges/) per [`docs/decisions/ADR-001-taxonomy.adoc`](docs/decisions/ADR-001-taxonomy.adoc).
- Schema-validation foundation: SHA-pinned mirror of [`hyperpolymath/standards/cartridges/cartridge-v1.json`](https://github.com/hyperpolymath/standards/blob/main/cartridges/cartridge-v1.json) under [`schemas/cartridge-v1.json`](schemas/cartridge-v1.json) (pin in [`schemas/PINNED-SHA`](schemas/PINNED-SHA), mirror discipline in [`schemas/SCHEMA-MIRROR.md`](schemas/SCHEMA-MIRROR.md)).
- Zero-dependency Deno validator at [`tools/validate-cartridges/`](tools/validate-cartridges/) with three tasks: `audit`, `audit-verbose`, `strict`.
- Strict-mode CI gate ([`.github/workflows/cartridge-schema.yml`](.github/workflows/cartridge-schema.yml)) live since 2026-06-01: any manifest that fails schema validation blocks the PR.
- Wave additions bundled into the v0.1 baseline: vector-DB cartridge wave (boj-server#100) and multi-modal cartridge wave (boj-server#101).
- Wiki bootstrapped with Home + Cartridge-Schema-Validation + Refresh-Discipline pages.
- Documented downstream consumer relationship (the on-demand fetch contract) at `boj-server#183`.

### Changed

- Drift-remediation campaigns closed in the run-up to the strict gate flip: #18 (`category` field backfill), #19 (`auth.method` enum mismatches), #20 (canonical-only / missing top-level fields / name-pattern renames). Post-remediation baseline: 139 / 139 manifests passing — see [`audits/cartridge-schema-2026-06-01.md`](audits/cartridge-schema-2026-06-01.md).

[0.1.0]: https://github.com/hyperpolymath/boj-server-cartridges/releases/tag/v0.1.0
