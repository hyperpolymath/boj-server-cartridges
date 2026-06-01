<!-- SPDX-License-Identifier: MPL-2.0 -->
<!-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath) -->

# panic-attack scan + hand-audit — cartridge schema validator foundation

**Date:** 2026-06-01
**Branch:** `feat/cartridge-schema-validator-foundation`
**Auditor:** automated panic-attack `assail` v2.1.0 + hand-audit
**Scope:** the six new/changed files introduced for the schema validator + audit-mode CI gate.

## Tool availability

panic-attack is fully runnable from this session: a pre-built release binary
exists at `/home/hyperpolymath/developer/repos/panic-attack/target/release/panic-attack`
(v2.1.0), and `assail` (its static-analysis subcommand) accepts `--headless --output-format json`
for non-interactive use. The analyzer maps `.ts`/`.tsx` to the JavaScript family
(see `src/assail/analyzer.rs` `language_detect_typescript_maps_to_javascript`
test); `.yml`/`.a2ml`/`PINNED-SHA` are scanned as `language: unknown` with the
generic pattern set. Four scans were executed at ~1s each — no extensive setup
was required. The pre-flight warning `failed to read AI manifest: reading A2ML
manifest 0-AI-MANIFEST.a2ml` was emitted (panic-attack expected `0-AI-MANIFEST.a2ml`
but the new file is `0.1-AI-MANIFEST.a2ml`); this is benign and does not affect
the assail pass.

## Scan results — panic-attack assail (headless)

| Target | Detected language | Lines | weak_points | unsafe / panic / unwrap | eval / io / threading |
|---|---|---|---|---|---|
| `tools/validate-cartridges/` (main.ts + main_test.ts) | javascript | 322 | 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| `.github/workflows/cartridge-schema.yml` | unknown | 50 | 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| `0.1-AI-MANIFEST.a2ml` | unknown | 89 | 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| `schemas/PINNED-SHA` | unknown | 14 | 0 | 0 / 0 / 0 | 0 / 0 / 0 |

panic-attack reported zero findings across every target. Note this is the
expected outcome for a small, dependency-light validator that does not use
`eval`, FFI, `unsafe`, dynamic require, or shell-out — i.e., panic-attack
has nothing to flag. A clean panic-attack run does not by itself prove the
absence of higher-level concerns (regex DoS, workflow injection, path
traversal); those are covered by the hand-audit below.

## Hand-audit — per file

### `tools/validate-cartridges/main.ts` (162 lines)

- **Injection (shell, eval, dynamic import):** none. Module imports are static
  `jsr:@std/...@1` only; no `eval`, no `new Function`, no `Deno.run` / shell-out.
- **Unsafe deserialisation:** `JSON.parse` of both the schema and each manifest;
  per-manifest parse is wrapped in `try / catch` and surfaced as a validation
  issue rather than crashing the walker (lines 106-114). Schema parse is *not*
  wrapped — acceptable because schema is repo-owned content gated by
  `PINNED-SHA`; a corrupt schema should fail loud.
- **Path traversal:** `walk(CARTRIDGES_DIR, …)` from `jsr:@std/fs@1`. `ROOT` is
  derived from `import.meta.url`; the walker is rooted at `cartridges/` under
  the repo. Read permission is the only granted capability (`--allow-read` in
  `deno.json`); no write/net/run/env. The validator cannot escape the repo even
  if a manifest path was attacker-controlled — and it isn't (paths come from
  the local filesystem walk, not from manifest content).
- **Regex DoS:** `new RegExp(schema.pattern).test(value)` at line 59 with a
  try/catch around it. The pattern source is `schemas/cartridge-v1.json`,
  which is content-pinned via `schemas/PINNED-SHA` and verified by CI
  (see workflow analysis below). The `value` side is manifest-controlled,
  but manifests are also repo-owned content. Therefore the only realistic
  catastrophic-backtracking surface is a malicious commit to either the
  schema or a manifest — i.e., a code-review concern, not a runtime one.
  No catch-and-continue swallow: bad-pattern errors are surfaced as
  validation issues, and a runaway match would block the CI job rather than
  silently pass. **Risk: informational.**
- **Resource use:** no streaming; every manifest is read in full via
  `Deno.readTextFile`. Cartridge manifests are sub-kB, ~150 of them; bounded.
- **Error handling:** `(e as Error).message` cast is benign — Deno's throw
  surface for `readTextFile`/`JSON.parse` is `Error`.

### `tools/validate-cartridges/main_test.ts` (162 lines)

- Tests are pure-data and pure-function; no FS, net, or shell. The inlined
  `validate` here intentionally mirrors `main.ts` to keep tests dependency-free
  — drift between the two definitions is the only concern, but it is a
  correctness/maintenance issue, not a security one.
- Note: line 57 (`new RegExp(schema.pattern).test(value)`) is **not**
  try/catch-wrapped in the test mirror, unlike `main.ts` line 58. This is a
  small drift between the two copies. **Risk: informational** (test inputs
  are hard-coded).

### `tools/validate-cartridges/deno.json`

- All tasks pass `--allow-read` only — least-privilege is correctly enforced.
  No `--allow-all`, `--allow-run`, `--allow-net`, or `--allow-env`.

### `.github/workflows/cartridge-schema.yml` (50 lines)

- **Workflow injection (`pwn-request`):** none. The job uses `actions/checkout@v4`
  without `ref: ${{ github.event.pull_request.head.sha }}` games, and the
  shell step does **not** interpolate any `${{ github.event.* }}` value into
  bash. `$GITHUB_STEP_SUMMARY` is the only env interpolation in shell and is
  a GitHub-supplied path. **Safe.**
- **Permissions:** `contents: read` at the workflow level; no per-job
  elevation. Correct for an audit-mode validator.
- **Concurrency:** `cancel-in-progress: true` keyed by workflow + ref — safe.
- **Action pinning:** `actions/checkout@v4` and `denoland/setup-deno@v2` are
  pinned to major-version tags, not commit SHAs. This matches the rest of the
  repo's workflows (`governance.yml` / `secret-scanner.yml` use the same
  convention) and the standards reusable's expectation, so calling it a
  finding here would be inconsistent. **Risk: low / consistent-with-estate.**
- **Schema-mirror SHA check:** the bash step uses `set -euo pipefail`,
  `sha256sum`, and a strict equality check before failing the job with an
  `::error::` annotation. Cannot be silently bypassed.

### `schemas/PINNED-SHA`

- TOML-ish key/value pairs only. No executable content. `canonical_commit` and
  `canonical_blob_sha` are 40-char hex; `content_sha256` is 64-char hex.
  Workflow extracts `content_sha256` via `awk -F'"' '/content_sha256/'` — a
  malicious value containing a `"` would simply fail the comparison rather
  than execute. Safe.

### `0.1-AI-MANIFEST.a2ml`

- Metadata-only YAML-ish manifest. No URLs that the validator follows, no
  template expansion, no executable hooks. The benign panic-attack warning
  about the filename (`0-AI-MANIFEST.a2ml` expected, `0.1-AI-MANIFEST.a2ml`
  actual) is a *discovery* gap, not a security gap — the file is still
  visible to humans and to the standards-side a2ml-validate.

## Risk classification

| Finding | Class |
|---|---|
| Regex DoS surface through user-supplied `schema.pattern` × manifest value | **informational** — both inputs are repo-owned + content-pinned + code-reviewed |
| `main_test.ts` mirrors `main.ts`'s `validate` without try/catch around `new RegExp` | **informational** — test inputs are hard-coded |
| Workflow uses major-tag action pins instead of commit SHAs | **low** — consistent with rest of repo, not a regression |
| panic-attack `0-AI-MANIFEST.a2ml` discovery filename vs new `0.1-AI-MANIFEST.a2ml` | **informational** — tool-side discovery gap, not a security issue |
| No medium/high findings | — |

## Recommendations

1. (Optional, low-priority) When the audit-mode gate flips to `--strict`,
   consider time-bounding the regex test in `main.ts` (e.g., schema-side
   `maxLength` on the matched value, or a Deno timer race) to defang the
   informational regex DoS surface. Defer until strict mode lands.
2. (Optional) Factor `validate` into a shared module so `main.ts` and
   `main_test.ts` cannot drift. This is a maintainability fix; current drift
   (try/catch on bad-pattern errors) is not exploitable.
3. (Optional, out-of-scope for this PR) File an issue against the parent
   session if you want a follow-up that pins `denoland/setup-deno@v2` and
   `actions/checkout@v4` to commit SHAs estate-wide — do not single-PR this
   workflow.
4. No changes are recommended inside the scope of this PR.

## Conclusion

**Safe to merge.** Both panic-attack `assail` (4 targets, 0 weak points) and
the hand-audit (6 OWASP-style categories per file) found no medium or higher
findings. The validator is correctly sandboxed (`--allow-read` only), the
workflow does not interpolate untrusted inputs into shell, the SHA-pin step
is fail-loud, and the only theoretical concern — regex catastrophic
backtracking through `schema.pattern` — is gated by the very SHA-pin
mechanism that this PR introduces.
