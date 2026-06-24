<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath) -->

# Contributing to boj-server-cartridges

`boj-server-cartridges` is the **canonical BoJ cartridge registry**. Hosts (`boj-server`, `panll`, others) fetch cartridges from this repo on demand into a host-local cache. Anything you land here ships to every downstream host on its next fetch — treat additions accordingly. Read [README.md](README.md) first for taxonomy + role suffixes; the canonical spec lives at [hyperpolymath/standards](https://github.com/hyperpolymath/standards/blob/main/cartridges/CARTRIDGE-FORMAT.adoc).

## The minimum bar

1. Every new `cartridge.json` MUST validate against [`schemas/cartridge-v1.json`](schemas/cartridge-v1.json). The schema is a SHA-pinned mirror of the canonical spec at [hyperpolymath/standards](https://github.com/hyperpolymath/standards/blob/main/cartridges/cartridge-v1.json); see [`schemas/SCHEMA-MIRROR.md`](schemas/SCHEMA-MIRROR.md) and [`schemas/PINNED-SHA`](schemas/PINNED-SHA).
2. CI runs the validator in **strict mode** — [`.github/workflows/cartridge-schema.yml`](.github/workflows/cartridge-schema.yml) blocks any PR that introduces an invalid manifest. The baseline is 139/139 passing as of 2026-06-01 ([`audits/cartridge-schema-2026-06-01.md`](audits/cartridge-schema-2026-06-01.md)).
3. Cartridge name MUST match `^[a-z0-9-]+-(mcp|lsp|dap|bsp|debug|format|lint|build|nesy|agentic|fleet)$`. See [README.md §"Cartridge roles"](README.md#cartridge-roles) for the role suffix table.
4. Commits MUST be GPG-signed.

## Workflow

```
cp -r cartridges/templates/gossamer-mcp \
      cartridges/domains/<your-domain>/<your-cartridge-name>
$EDITOR cartridges/domains/<your-domain>/<your-cartridge-name>/cartridge.json
cd tools/validate-cartridges && deno task audit
```

`deno task audit` walks every manifest in the tree and prints a one-line summary per cartridge; exit 0 regardless. `deno task audit-verbose` expands each violation. `deno task strict` is the CI gate — run it locally before pushing if your change touches manifests at scale.

| Where | What |
|---|---|
| `cartridges/domains/<domain>/<name>/` | Domain-bound cartridges (cloud, database, ci-cd, languages, security, research, …). |
| `cartridges/cross-cutting/<category>/<name>/` | Cartridges not bound to a single domain (agentic, nesy, build, debug, fleet, health). |
| `cartridges/templates/gossamer-mcp/` | Canonical scaffold. Use this as the starting point for new cartridges. |

Taxonomy ratified in [`docs/decisions/ADR-001-taxonomy.adoc`](docs/decisions/ADR-001-taxonomy.adoc).

## PR discipline

- **Auto-merge is enabled by default for this repo.** Open the PR, mark it auto-merge, let CI do its job.
- One cartridge per PR where possible. Cartridge-wave PRs (e.g. the vector-DB / multi-modal waves bundled into v0.1) are the exception — call them out in the PR description and link the upstream campaign.
- Cross-link the canonical schema home ([hyperpolymath/standards](https://github.com/hyperpolymath/standards/tree/main/cartridges)) in PR descriptions when proposing schema-shape changes; those land upstream first, then mirror here via a `PINNED-SHA` bump.

## CI / required checks

Required status-check workflows must **always report**. Never add `on.*.paths` to a required workflow (`proofs.yml`, `zig-test.yml`, `foundry.yml`): a path-filtered required check that doesn't trigger is reported as permanently "Expected" and leaves the PR `blocked` even when green. The estate pattern — keep the workflow always-triggered, add an always-run `changes` job that recomputes the gate's path set via `git diff origin/<base>...HEAD`, and gate each heavy job with `needs: changes` + `if: needs.changes.outputs.run == 'true'` (a job skipped via `if:` counts as a passing required check). Fail safe: default to running. Mirrors boj-server's gates (boj-server PR #216, this repo PR #45).

## What lives elsewhere

- The cartridge **spec** itself (schema shape, role suffix conventions, version semantics): [hyperpolymath/standards](https://github.com/hyperpolymath/standards) `cartridges/`.
- The cartridge **host runtime** (catalog refresh, fetch contract, tray UI): [hyperpolymath/boj-server](https://github.com/hyperpolymath/boj-server) — fetcher contract documented at `boj-server#183`.
- Cross-cartridge integration patterns, walkthroughs, the refresh-discipline page: the [wiki](https://github.com/hyperpolymath/boj-server-cartridges/wiki).

## Machine-readable summary

[`0.1-AI-MANIFEST.a2ml`](0.1-AI-MANIFEST.a2ml) is the project's machine-readable manifest. Update it when adding a top-level structural element (a new domain, a new role suffix, a new tool under `tools/`).
