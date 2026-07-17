# CLAUDE.md - AI Assistant Instructions

## Machine-Readable Artefacts

This repo follows the hyperpolymath standard. See
`https://github.com/hyperpolymath/standards` for the canonical 6-file
`.machine_readable/` layout (STATE/META/ECOSYSTEM/AGENTIC/NEUROSYM/PLAYBOOK in
A2ML format). The root AI manifest is `0-AI-MANIFEST.a2ml`.

---

## Language Policy (Hyperpolymath Standard)

The full policy is canonical in `hyperpolymath/standards`. Key points for this
repo:

- **No new TypeScript or ReScript** — convert existing `.ts`/`.res` to
  AffineScript (`.affine`) directly.
- **Deno** for the runtime, not Node. `deno.json` for imports; no
  `node_modules` in production.
- **AffineScript** for new application code.

### General rule — proactive TS/ReScript → AffineScript conversion

**Convert any `.ts` / `.res` (or otherwise-banned front-end language) to
AffineScript at the earliest opportunity** — treat it as standing background
work, not a one-off. Two guardrails keep this honest:

1. **Portable-now only.** The `js-to-affinescript` migration doctrine
   (`standards/docs/migrations/js-to-affinescript`) carves out MCP/LSP protocol
   glue and VSCode-host code: *"MCP glue … Should NOT appear in `portable now`."*
   Those stay until the AffineScript MCP/LSP/VSCode bindings ship (affinescript#446
   top-50 roadmap). Genuinely-portable Deno CLI scripts (e.g. `tools/*.ts` here)
   are the convert-now bucket.
2. **Compile-verify, wire-first.** A port is not done until the `.affine`
   builds green (`just check`) and the compiled `.mjs` is wired as the live
   entry with the original `.ts`/`.res` removed *in the same PR*. Never ship an
   unbuilt `.affine` or delete a working `.ts` for one that hasn't compiled.

Reference idiom: `standards/0-ai-gatekeeper-protocol/mcp-repo-guardian/src/*.affine`
(an AffineScript MCP server importing `@modelcontextprotocol/sdk`).

### TypeScript / ReScript Exemptions (adapters)

The "no new TS/ReScript" rule has approved exemptions in this repo — **the
cartridge MCP/LSP adapters and the VSCode-host LSP panels**. These are the
estate's recognised carved-out class (protocol glue against TS-native SDKs); the
same carve-out `boj-server` already documents for its 6 adapters. They are not
policy violations.

| Path | Files | Class | Rationale | Unblock condition |
|---|---|---|---|---|
| `cartridges/**/adapter/**` (`*.ts`) | 34 | MCP/LSP adapter glue | `@modelcontextprotocol/sdk` + LSP libs are TS-native; doctrine keeps MCP/LSP glue out of `portable now`. | AffineScript MCP + LSP bindings (affinescript#446). |
| `cartridges/**/panels/**` (`*.res`) | 3 | VSCode-host LSP panels | `VscodeApi`/`LanguageClient`/`Extension` target the VSCode extension-host API — same class as the estate's `**/vscode/**` carve-out. | AffineScript VSCode-extension API binding (top-50 roadmap). |

Explicitly **not** exempt: `tools/*.ts` (6 files) — portable-now Deno CLI, in the
normal convert-now bucket per the general rule above.

The canonical source of truth is the `path_allow_prefixes` field on the hypatia
rules `cicd_rules/typescript_detected` and `cicd_rules/rescript_detected` in
`hyperpolymath/hypatia`; this table mirrors that for human readability. Adding to
this list requires explicit owner approval and an unblock condition.

### Documentation Format

- All docs `.adoc` (AsciiDoc) except GitHub-required files (SECURITY.md,
  CONTRIBUTING.md, CODE_OF_CONDUCT.md, CHANGELOG.md).

---

## ABI / FFI / Adapter Baseline (verified 2026-07-17)

Every cartridge's interface stack is three layers, in these languages, no
exceptions:

| Layer | Language | Role |
|---|---|---|
| **ABI** | **Idris2** | Formally verified contract — dependent-type proofs, state machine or exposure-gate invariants, `%default total`, zero `believe_me`/`postulate`/`assert_total` in the trusted core. |
| **FFI** | **Zig** | C-ABI implementation (ADR-0006 five-symbol pattern: `boj_cartridge_{init,deinit,name,version,invoke}`). |
| **Adapter** | **Zig** | The base-level API/service surface — see below. |

A cartridge is not complete without all three directories: `abi/`, `ffi/`,
`adapter/` (plus `panels/`, `tests/`). The minting template
(`cartridges/templates/gossamer-mcp/`) ships all three; do not omit `adapter/`
when minting or completing a cartridge — it is not optional scaffolding.

### The "unified adapter"

Current canonical shape (reference implementation:
`cartridges/domains/config/k9iser-mcp/adapter/`): **one loopback listener**,
protocol-classified (REST `/invoke`, SSE `/sse`, GraphQL `/graphql`, gRPC-compat
`/grpc/<Svc>/<Method>`), funneling every request through a **transaction gate**
(`exposureSatisfied`, mirroring the cartridge's own Idris2 exposure contract
when it has one) before a single dispatch call into the one Zig ABI
(`ffi.boj_cartridge_invoke`). Invariants (from the adapter READMEs, verbatim):

- **Stateless** — all state lives behind the FFI, never in the adapter.
- **Response passthrough** — whatever the FFI returns goes back to the wire
  unmodified (no embellishment, no silent recovery).
- **`cartridge.json` is source of truth** for the tool catalogue; drift between
  adapter and manifest is a CI failure.
- **Internal-only, never a public ingress.** Per ADR-0004 the only governed
  public surface is the `http-capability-gateway` (tier-2); adapters bind
  loopback and sit behind it.

Naming lineage: the fuller 16-protocol-surface pattern is called the
**Hexadeca-Connector** elsewhere in the estate (`hyperpolymath/hypatia`,
`hyperpolymath/proven-servers`) — same Idris2-ABI + Zig-FFI substrate, more
protocol surfaces. It descends from a now-**retired** V-lang reference
(`developer-ecosystem/v-ecosystem/v_api_interfaces/v_api_interfaces.v`),
replaced across the estate by Zig+Idris2(+Rust-client where relevant) per the
V-lang ban (2026-04-10). Cartridge `adapter/` dirs keep a `SIDELINED-*.v.adoc`
note documenting what was replaced — never resurrect the V version, and never
substitute anything but Zig for a new adapter.
