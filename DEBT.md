<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
<!-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk> -->

# Technical debt register

One index of known debt in this repository, measured 2026-08-07 against `main`.
Every item carries **the command that produced the evidence**, so any row can be
re-checked or falsified in one step. Claims that are not verified are labelled
**DIAGNOSIS (unconfirmed)** rather than asserted.

The sibling host keeps its own register at
[`boj-server/DEBT.md`](https://github.com/hyperpolymath/boj-server/blob/main/DEBT.md);
cross-repo items are noted in both and fixed once.

Severity: **HIGH** — actively misleads, or a gate that cannot fail ·
**MEDIUM** — wrong but self-evident on contact · **LOW** — cosmetic or historical.

---

## The single largest item

**99 `adapter/` trees do not compile, and no CI job builds them.** This is not
0.16 fallout — it predates the migration. `zig-test.yml` globs only `*/ffi/`, so
the adapter layer has never been gated; the template adapter calls an `init`
symbol its own FFI never defines, and the FFI's `export fn`s are not `pub`, so the
module import cannot see them either. Because `just mint` copies the template,
**every minted cartridge inherits the defect**. Meanwhile `.claude/CLAUDE.md`
tells contributors "a cartridge is not complete without all three directories"
and "do not omit `adapter/` when minting" — pointing them straight at 99
non-compiling build files. See A-1.

```sh
find cartridges -path '*/adapter/build.zig' | wc -l    # 99
grep -rn 'gossamer_init' cartridges/templates/gossamer-mcp/
```

---

## Adapters — A

| ID | Sev | Item | Evidence |
|----|-----|------|----------|
| A-1 | HIGH | 99 `adapter/build.zig` trees, none built by CI, template broken at the call site (see above). Needs: fix the template wiring, port the cloned `std.net` listener to `std.Io.net`, rewrite the 99 build files to the shape `cartridges/domains/config/k9iser-mcp/adapter/build.zig` already uses (it is the only 0.16-valid one), then extend `zig-test.yml`'s glob. | `find cartridges -path '*/adapter/build.zig' \| wc -l` |
| A-2 | MEDIUM | 125 `adapter/` dirs exist but only 99 have a `build.zig` — 26 are scaffolding that nothing, including the new `full-sweep`, will ever touch. Same shape on the FFI side: 131 `ffi/` dirs, 118 with a `build.zig`. | `find cartridges -type d -name adapter \| wc -l` vs `find cartridges -path '*/adapter/build.zig' \| wc -l` |
| A-3 | MEDIUM | `.claude/CLAUDE.md` documents an invariant the tree violates ("not complete without all three directories"). Either the invariant or the tree has to give; right now the document is the thing that is wrong. | `grep -n 'not complete without' .claude/CLAUDE.md` |

---

## Licence — L

| ID | Sev | Item | Evidence |
|----|-----|------|----------|
| L-1 | HIGH | **480 files carry `CC-BY-SA-4.0` headers while root `LICENSE` is MPL-2.0, and there is no `NOTICE` and no `.reuse/dep5` to declare the split.** A scanner reading only `LICENSE` mis-attributes every one of them. The sibling repo does this correctly — copy its `NOTICE` + `.reuse/dep5` pattern. | `ls .reuse NOTICE` → absent · `grep -rl 'CC-BY-SA-4.0' --include='*.adoc' --include='*.md' . \| wc -l` → 480 |
| L-2 | MEDIUM | 12 `_source-archive/` trees carry vendored source with **no SPDX header and no provenance record** — no statement of origin or upstream licence. | `find cartridges -type d -name _source-archive \| wc -l` |
| L-3 | LOW | Five `minter.toml` files lack SPDX headers while every other `.toml` has one. | `git ls-files '*minter.toml' \| xargs grep -L SPDX` |
| L-5 | MEDIUM | `cartridges/domains/gaming/idaptik-admin-mcp/panels/manifest.json` declares **`AGPL-3.0-or-later`** in an otherwise MPL-2.0 / CC-BY-SA-4.0 repo. **Flagged, deliberately not changed** — the estate has a history of licence-clobber sweeps flattening genuine AGPL work, so this needs an owner ruling, not a script. | `grep -rn AGPL cartridges --include='manifest.json'` |
| L-4 | LOW | `.github/funding.yml` and `.github/FUNDING.yml` both exist and differ. GitHub reads only the uppercase one; the lowercase one is dead weight and also lacks SPDX. | `ls .github/[fF][uU][nN][dD][iI][nN][gG].yml` |

---

## Truthfulness — T

The estate's central promise is that the catalogue never advertises capability it
cannot back. That invariant currently holds — but nothing in this repository
enforces it.

| ID | Sev | Item | Evidence |
|----|-----|------|----------|
| T-1 | HIGH | **92 of 142 FFI implementations return canned stub JSON** (`"status":"stub"`). The per-file headers are honest about it; the scale is the debt — roughly two-thirds of the advertised surface is not wired to anything. | `grep -rl '"status":"stub"' cartridges --include='*_ffi.zig' \| wc -l` → 92 |
| T-2 | HIGH | **130 of 142 manifests omit `available` entirely**; 12 set it `true`; none sets it `false`. The field is the host's only machine-readable signal for "this is real", and for most cartridges it is simply absent. | `grep -rL '"available"' cartridges --include='cartridge.json' \| wc -l` |
| T-3 | MEDIUM | The stub↔available invariant is **honoured but unenforced here**: no cartridge advertising `available: true` returns a stub. The gate that checks this (`tests/truthfulness_check.sh`) lives in boj-server, which no longer holds the cartridges. The check should run where the manifests are. | cross-check the 12 `available: true` manifests against their `*_ffi.zig` |

---

## Proof — P

115 `.idr` files with **zero** `believe_me`, `postulate`, `assert_total`, `sorry`,
`%default partial` or `?hole`. The proofs are clean; the gate around them is not.

| ID | Sev | Item | Evidence |
|----|-----|------|----------|
| P-1 | HIGH | **`proofs.yml` has no `schedule:` trigger.** The sibling repo added a weekly cron precisely because a proof break that already lives in `main` is otherwise never re-detected — that is how a duplicate lemma sat in main behind a green gate. This repo has 115 proofs, 23 of which had already silently rotted once, and no such backstop. | `grep -n 'schedule' .github/workflows/proofs.yml` → absent |
| P-2 | MEDIUM | `scripts/check-trusted-base.sh` states "boj-server sanctions EXACTLY 5 class-(J) axioms". It is 4 — `charEqSym` was discharged 2026-06-24 and the enforcing constant there is `EXPECTED_AXIOMS=4`. Cross-repo stale claim. | `grep -n 'EXACTLY' scripts/check-trusted-base.sh` |
| P-4 | MEDIUM | **18 of 126 `abi/` directories contain no `.idr` file at all** — the layer is present as scaffolding but carries no proof, while the three-layer contract implies one. | `for d in $(find cartridges -type d -name abi); do [ -z "$(find $d -name '*.idr')" ] && echo $d; done \| wc -l` |
| P-3 | LOW | **ADR-0006 is cited by all 118 shims and every `ffi/build.zig`, but no ADR-0006 exists in this repo** — only `ADR-001-taxonomy` and `ADR-002`. Now that this repo is canonical for cartridges, the five-symbol contract must be resolvable from here. Note also the numbering clash (`ADR-00N` local vs `ADR-000N` cited). | `ls docs/decisions/` |

**Positive control:** this repo's `scripts/typecheck-proofs.sh` already carries a
vacuous-pass guard that the sibling lacked until 2026-08-07. Each repo held half
the protection.

---

## Test — T2

| ID | Sev | Item | Evidence |
|----|-----|------|----------|
| T2-1 | HIGH | **52 cartridge test scripts exist and no workflow runs any of them.** `zig-test.yml` runs `zig build test` inside changed `ffi/` dirs and nothing else. | `grep -rn 'tests/' .github/workflows/` → no matches |
| T2-2 | HIGH | **88 of 142 cartridges have no test directory at all** — overlapping heavily with the 92 that return stubs. | `find cartridges -type d -name tests \| wc -l` → 54 |
| T2-3 | LOW | The new `full-sweep` job builds every cartridge FFI but is `schedule` + `workflow_dispatch` only, by design (a required full build would strand PRs). Worth knowing it is not a per-PR guarantee. | `grep -n 'full-sweep' -A4 .github/workflows/zig-test.yml` |

---

## CI/CD — C

| ID | Sev | Item | Evidence |
|----|-----|------|----------|
| C-1 | HIGH | `.github/workflows/main-estate-audit.yml` is **untracked**, has **no `permissions:` block**, and pins **27 actions to `@main`/`@v4`** rather than SHAs. It has therefore never run. Identical file, identical defects, in the sibling repo. | `git status --porcelain .github/workflows/` |
| C-2 | MEDIUM | `pages.yml` (GitHub Pages via Ddraig SSG) and `pages-deploy.yml` (Cloudflare Pages) both fire on push to main, to different hosts, with no coordination. `pages.yml` copies `README.md` into its source dir — **that file does not exist** (converted to `.adoc`), so it publishes a one-line stub. | `grep -n 'README.md' .github/workflows/pages.yml` |
| C-3 | MEDIUM | GitHub Pages 404s for this repo, and issue #97 records that the Cloudflare Pages deploy has never succeeded (missing secrets + DNS). Two deploy paths, neither demonstrably working. | `curl -s -o /dev/null -w '%{http_code}' https://hyperpolymath.github.io/boj-server-cartridges/` |
| C-5 | HIGH | **`hypatia-scan.yml` cannot fail.** The scan runs `--exit-zero` *and* is suffixed `\|\| true` — double suppression. It is credited as a security gate and reports success unconditionally, whatever it finds. | `grep -n 'exit-zero' .github/workflows/hypatia-scan.yml` |
| C-6 | LOW | `flake.nix` ships `just` alone in its dev shell while claiming to "mirror the build tooling actually present in this repo" — no `zig`, `deno` or `idris2`, so `nix develop` cannot build or test anything. | `grep -n 'packages = with pkgs' flake.nix` |

---

## Code — D

| ID | Sev | Item | Evidence |
|----|-----|------|----------|
| D-1 | HIGH | Three batch-fix tools hardcode `ROOT = "/home/hyperpolymath/developer/repos/boj-server-cartridges"` — **a path that is wrong even on the original machine** (the repo lives under `hyper-repos/`). Already broken, not merely unportable. | `grep -rn 'developer/repos/' tools/` |
| D-2 | MEDIUM | `cartridges/domains/languages/007-mcp/ffi/oo7_mcp_ffi.zig` has an absolute `/var/mnt/eclipse/repos/boj-server/cartridges/007-mcp/...` path baked into shipped FFI source, pointing into the **retired** tree of the other repo. | `git grep -n '/var/mnt/eclipse'` |
| D-3 | MEDIUM | Machine-specific binary paths in distributed config: `lsp-mcp/presets.json` points at a user-specific `rust-analyzer`; `codeseeker-mcp` FFI has `/home/hyper/repos/myproject`. | `git grep -n '/home/hyper'` |
| D-4 | MEDIUM | *(remediation in flight)* **A `v` → `zig` find/replace corrupted ~140 adapter READMEs and `PLAYBOOK.a2ml`**, which now read as *banning Zig* ("Banned: ziguage", "zig ban validator") in a repo whose entire FFI layer is Zig. The banned language was **V**, which Zig replaced. Agent-hostile: it is machine-readable content asserting the opposite of the truth. | `grep -rln 'zig banned 2026-04-10\|zig predecessor' cartridges \| wc -l` |
| D-5 | MEDIUM | *(remediation in flight)* `.machine_readable/6a2/` is **another repository's boilerplate**: `STATE.a2ml` says `project = "rsr-template-repo"`, `ECOSYSTEM.a2ml` says `project = "pseudoscript"`. An agent following `0-AI-MANIFEST.a2ml`'s read order is fed facts about two unrelated projects. | `grep -n '^project' .machine_readable/6a2/*.a2ml` |
| D-6 | LOW | `site/catalog.json` is hand-maintained with **no generator**, so the public site's counts drift permanently and it is already missing in-tree cartridges. | `grep -rl catalog.json .github/ tools/ scripts/ Justfile` → nothing |

---

## Documentation — X

| ID | Sev | Item | Evidence |
|----|-----|------|----------|
| X-1 | HIGH | Counts disagree three ways across the estate: this repo's README says **139**, boj-server says **125**, disk says **142**. | `find cartridges -name cartridge.json \| wc -l` |
| X-2 | MEDIUM | `CHANGELOG.md`'s last entry is `[0.1.0] — 2026-06-01` with **71 commits unrecorded**, no `[Unreleased]` section, and a link to a `v0.1.0` release tag **that does not exist** (`git tag` is empty). | `git log --oneline --since=2026-06-01 \| wc -l` · `git tag` |
| X-3 | MEDIUM | `CONTRIBUTING.md` and `SECURITY.md` both link `README.md` — converted to `.adoc`, so the contributor on-ramp opens with dead links. `MAINTAINERS.adoc` links `.adoc` names for files that exist as `.md`. | `grep -n 'README.md' CONTRIBUTING.md SECURITY.md` |
| X-4 | MEDIUM | `GOVERNANCE.md` violates the repo's own `.adoc`-only policy **and** `Mustfile.a2ml` requires `GOVERNANCE.adoc`, which was deliberately deleted. The contractile check fails against the tree it governs. | `grep -n 'GOVERNANCE' .machine_readable/contractiles/Mustfile.a2ml` |
| X-5 | LOW | No cartridge-authoring guide in `docs/` — the abi/ffi/adapter layer contract exists only in `.claude/CLAUDE.md`, a tool config file humans will not find. | `ls docs/` |

---

## How to use this file

Add an item when you find debt you are not fixing in the same change. Give it the
next ID in its domain, a severity, and — non-negotiably — **a command that
reproduces the evidence**. An item without a reproducible check is an opinion, and
opinions rot silently. Remove an item only when its command proves it gone.
