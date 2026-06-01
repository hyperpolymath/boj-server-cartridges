<!--
SPDX-License-Identifier: MPL-2.0
Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
-->

# Echo-types integration audit — boj-server-cartridges

**Date:** 2026-06-01
**Auditor:** parent session (cartridges-side architectural audit)
**Upstream under audit:** `hyperpolymath/echo-types` (constructive Agda library at `/home/hyperpolymath/developer/repos/echo-types`)
**Standing obligation discharged by this doc:**
`feedback_proofs_must_check_and_cross_doc_echo_types` (owner directive 2026-06-01).
Every cartridges-side architectural decision must explicitly check echo-types
relevance, reuse if applicable, extend upstream WITH proofs if not, and
cross-document. This file is the cartridges-side cross-doc artifact for the
audit; the upstream echo-types side already documents one cartridges
consumer in `local-coord-mcp/abi/LocalCoord/PROOF-SCHEDULE.adoc` (Phase 3
obligations P-17 / P-18).

## TL;DR

* **Schemas-as-data (Section A):** echo-types is **NOT load-bearing** for the
  `cartridge.json` schema itself. The schema is a flat capability manifest
  (name / domain / tier / protocols / tools / FFI), not a residue/loss
  carrier. No structural-loss vocabulary belongs at that layer.
* **Schemas-as-runtime-output (Section A, second half):** a small number of
  cartridges produce *result-with-information-loss* at runtime —
  notably `codeseeker-mcp` (Reciprocal Rank Fusion hybrid search +
  knowledge-graph rerank). For these, echo-types is **potentially
  load-bearing in the future**, but only at the *proof* layer (Section B),
  not in the cartridge.json schema.
* **Proofs (Section B):** **NOT load-bearing today.** 112 Idris2 `.idr` proofs
  exist under `cartridges/**/abi/`; all 112 are protocol-shape / state-machine
  / safety-witness style. Exactly **one** cartridge —
  `cross-cutting/agentic/local-coord-mcp` — has explicit echo-types
  obligations (P-17 audit/summary/hash-chain, P-18 tropical TTL/trust),
  both **deferred to Phase 3** by `PROOF-SCHEDULE.adoc`. No other cartridge
  has surfaced an echo-types obligation in its design log.
* **Obligation status (Section C):** this audit **closes the
  cross-doc obligation for boj-server-cartridges as of 2026-06-01.** Going
  forward, new architectural docs / ADRs in this repo MUST include a
  one-line "Echo-types audit: <result>" footnote.
* **Concrete next actions (Section D):** zero blocking actions today. Three
  watch items (Phase 3 local-coord, codeseeker-mcp RRF, kategoria-mcp
  ranking) with documented trigger conditions.

## A. Echo-types as load-bearing for cartridge SCHEMAS

### A.1 The `cartridge.json` schema itself: NOT load-bearing

The canonical cartridge schema is anchored at `https://boj.dev/schemas/cartridge/v1.json`
and is instantiated in 139 manifests across this repo. Two representative
samples:

* `cartridges/templates/gossamer-mcp/cartridge.json` — fields: `name`,
  `version`, `description`, `domain`, `tier`, `protocols`, `auth`, `api`,
  `tools` (with `inputSchema`), `ffi`. Pure capability advertisement.
* `cartridges/cross-cutting/agentic/local-coord-mcp/cartridge.json` —
  same shape plus `bind` (loopback + port), `federation: "none"`. Again
  pure capability advertisement; the only "loss" expressed at schema
  level is `federation: "none"` (a policy choice, not a residue).

Mapping echo-types vocabulary against this:

| echo-types concept | applies to `cartridge.json`? | why / why not |
|---|---|---|
| `Echo f y := Σ A (λ x → f x ≡ y)` | NO | A manifest is not the output of an irreversible map — it IS the source declaration. |
| `ResidueForm f R` (Tier 2, eight instances) | NO | The schema carries no residue field. Capability adverts ≠ residues. |
| `LossTaxonomy` (EQUIV/INJ/SURJ/CONST function-axis) | NO | Manifests are not functions to be classified. |
| `DecorationStructure` (graded / linear / access lattices) | NO | Tiers (Ayo/Aral/Aha/etc.) are administrative classifications, not residue lattices. The mapping would be forced. |
| `Provenance` audience surface | borderline | A manifest does carry author + version + SPDX, but that is build-time provenance handled by SPDX-FileCopyrightText, NOT semantic-fibre provenance over an irreversible computation. |
| `Security` audience surface | borderline | `local-coord-mcp` carries `loopback_only: true`. That's a region-exit-style claim, but it's a boolean policy, not a region-exit *audit* with retained witness. |

**Verdict.** The cartridge.json schema lives below echo-types' use cases.
Adding `--echo:` fields to manifests would be premature taxonomy. The
schema's job is *exact preservation* (validator-checked); echo-types
explicitly tells callers to "use exact preservation when available"
(`README.md` §"Semantic Fibre Vocabulary"):

> They are not a replacement for ordinary type checking, ABI proofs, FFI
> discipline, typed-wasm, structural-fit systems, or any boundary system
> that can preserve exact guarantees. When exact preservation is
> available, use it.

The cartridge schema falls under "any boundary system that can preserve
exact guarantees".

### A.2 Cartridge runtime OUTPUTS: potentially load-bearing for a small subset

A different question is whether the *values cartridges return* exhibit
structured loss. Surveying the 139 cartridges, the candidates are:

| Cartridge | Runtime output shape | Echo-shaped? |
|---|---|---|
| `domains/development/codeseeker-mcp` | Hybrid search via Reciprocal Rank Fusion (vector + text + path) + knowledge-graph rerank | **YES, latent.** RRF over heterogeneous rankers is exactly a non-injective fusion: the fused order forgets which sub-ranker contributed each rank. Echo language fits as `Echo fuse fused_score = Σ (vector_score, text_score, path_score) (fuse(...) ≡ fused_score)`. The residue is the per-ranker contribution. |
| `domains/education/kategoria-mcp` | Knowledge-domain ranking | **YES, latent.** Same pattern: any rank-fusion produces a result with constraint-on-source but not source-reconstruction. |
| `domains/knowledge/librarian-mcp` + `obsidian-mcp` + `zotero-mcp` | Document retrieval | **YES, latent.** Retrieval-with-rank is the canonical echo-types use case per `EchoTropical` (argmin / argmax witnesses). |
| `domains/gaming/npc-mcp` (Perception.idr) | NPC perception state | **borderline.** Perception is a projection from world-state to belief-state — formally an echo, practically not yet stated that way. |
| Everything else (118+) | Either state-machine transitions (idempotent), CRUD on external resources (exact), or message-passing (typed) | NO |

For the YES-latent cartridges, the echo-types relevance is **at the proof
level**, not at the cartridge.json level. None of them currently declare a
proof obligation against echo-types; see Section B.

## B. Echo-types as load-bearing for cartridge PROOFS

### B.1 Enumeration of `.idr` proofs under `cartridges/**/abi/`

Running `find /home/hyperpolymath/developer/repos/boj-server-cartridges/cartridges -name "*.idr" -path "*/abi/*"` returns **112 files**. (Total `.idr`
under `cartridges/` including non-abi paths: 112 — every `.idr` lives under
an `abi/` directory; there are no top-level idr files.)

Sampling the shapes:

* Most cartridges ship a `Protocol.idr` or `Safe*.idr` defining:
  * an enum of states (e.g. `IndexState` in
    `codeseeker-mcp/abi/CodeseekerMcp/SearchGraph.idr` —
    `Uninitialised | Indexing | Ready | Querying | IndexError`),
  * a `ValidTransition` GADT enumerating allowed state edges,
  * a runtime predicate (`canIndexTransition`),
  * a `%default total` discipline.
* `local-coord-mcp/abi/LocalCoord/SafeLocalCoord.idr` is the canonical
  template: loopback-bind witnesses, port-range witnesses, session-token
  non-emptiness, federation-policy uninhabitedness.
* `ephapax-mcp/abi/Ephapax.idr`, `typed-wasm-mcp/abi/TypedWasm/Protocol.idr`,
  `affinescript-mcp/abi/AffinescriptMcp/SafeCompiler.idr` —
  language-tool wrappers; protocol-shape only.

**None of the 112 proofs use echo-types vocabulary directly.** None imports
`Echo`, `EchoResidue`, `EchoTropical`, `EchoLossTaxonomy`, or any other
echo-types module. (Mechanically expected: Idris2 cannot import Agda
modules anyway; the integration would be at the design / specification
level, with parallel sibling proofs.)

### B.2 The single explicit echo-types touch-point: `local-coord-mcp`

`cartridges/cross-cutting/agentic/local-coord-mcp/abi/LocalCoord/PROOF-SCHEDULE.adoc`
is the only cartridges-side document that names echo-types. Relevant
entries from the schedule table:

| # | Obligation | Status | Prover |
|---|---|---|---|
| P-17 | Echo-type formalisation of audit + summary + hash chain | **Phase 3 (deferred)** | Agda (echo-types repo) |
| P-18 | Tropical-semiring model of TTL + trust | **Phase 3 (deferred)** | Agda (EchoTropical) |

The schedule's prose §"Notes on prover choice" explicitly frames the
boundary:

> Agda enters only for Phase 3 echo-type + tropical work, consuming the
> `echo-types/` bridge library. **No echo-type obligation lives inside the
> cartridge repo — it lands upstream in `echo-types/` with coord as the
> dogfood consumer.**

This is the correct discipline. The cartridge ships Idris2 protocol-shape
proofs (P-04 through P-13 are P0/P1/P2 in Phase 1); the echo-type work
(P-17 / P-18) lives upstream in echo-types and the cartridge consumes it
as a dogfood case study. Phase 3 is gated on Phase 2 (P-15 choreographic
types, P-16 epistemic types) which are themselves deferred.

### B.3 Other cartridges with echo-shaped runtime output but no echo-types
obligation yet

Cross-referencing Section A.2's YES-latent list against B.1's proof
inventory:

* `codeseeker-mcp/abi/CodeseekerMcp/SearchGraph.idr` — proves state-machine
  validity for index lifecycle. Does NOT prove anything about the
  Reciprocal Rank Fusion semantics. **Could** benefit from an
  echo-types-side parallel proof (`Echo fuse fused_score`) — see D.2.
* `kategoria-mcp/abi/Kategoria/Protocol.idr` — protocol shape only.
* `librarian-mcp` / `obsidian-mcp` / `zotero-mcp` — protocol/registry
  shape only; retrieval semantics not proved.
* `npc-mcp/abi/NpcMcp/Perception.idr` — perception state-machine; the
  "world-state to belief-state" projection is implicit, not type-level.

None of these has filed a proof obligation against echo-types. None has a
PROOF-SCHEDULE.adoc equivalent. The cartridges-side rule remains:
echo-type obligations land upstream in `hyperpolymath/echo-types` with
the cartridge as dogfood consumer — they do NOT land in this repo.

### B.4 Why parallel siblings (not direct integration)

Mechanically: Idris2 and Agda do not share a proof kernel. The integration
shape recommended by the local-coord PROOF-SCHEDULE is:

1. Cartridge-side: Idris2 proves the protocol shape (states, transitions,
   invariants on FFI boundaries). 
2. Upstream echo-types: Agda proves the echo-type semantics of the lossy
   runtime operation (audit, summary, hash chain, rank fusion).
3. Cross-doc reference: the cartridge's PROOF-SCHEDULE names the upstream
   echo-types theorem; the upstream `cross-repo-bridge-status.md` (in
   echo-types) names the cartridge as a consumer.

The upstream echo-types `cross-repo-bridge-status.md` is the canonical
ledger for parallel-sibling pairings. As of 2026-06-01 that ledger does
NOT yet list `local-coord-mcp` (because P-17/P-18 are Phase 3 deferred and
no Agda proof has been written upstream); when Phase 3 opens, the
forward-link should be added at both ends.

## C. Cross-doc obligation status for boj-server-cartridges

### C.1 Closure as of 2026-06-01

The standing obligation from `feedback_proofs_must_check_and_cross_doc_echo_types`
(owner directive 2026-06-01) is satisfied for boj-server-cartridges by
this audit, on the following grounds:

* **L1 / L4 audit completeness.** The cartridge schema is L1 (capability
  manifest) + L4 (FFI / wire format) only. L1/L4-only obligations
  "audit-and-record-as-not-relevant" per the directive; this file is
  that record.
* **L3 (echo) audit completeness.** Exactly one cartridge
  (`local-coord-mcp`) has an L3 echo touch-point. That touch-point is
  already cross-documented at `local-coord-mcp/abi/LocalCoord/PROOF-SCHEDULE.adoc`
  P-17 + P-18, with the upstream-as-source-of-truth discipline already
  spelled out. This audit confirms that documentation is still correct
  and does not need amendment as of 2026-06-01.
* **Forward-going hook.** All new architectural docs / ADRs in this repo
  MUST include a one-line "Echo-types audit: <result>" footnote going
  forward; see C.2 for the recommended footnote forms.

### C.2 Mandatory footnote for future ADRs / architecture docs

Every new doc under `/home/hyperpolymath/developer/repos/boj-server-cartridges/docs/decisions/`
(ADRs) and every new architectural note in `docs/handover/` MUST close with
one of these three forms:

* **`Echo-types audit: not relevant (L1/L4 only).`** — for ADRs about
  schema fields, FFI / wire format, cartridge taxonomy, or build/CI.
  This is the expected default for ~95% of cartridges-side ADRs.
* **`Echo-types audit: defer to upstream <module>.`** — when the cartridge
  has an L3-echo touch-point that should be proved upstream in
  echo-types. Cite the upstream module by name (e.g. `EchoTropical`,
  `EchoProvenance`).
* **`Echo-types audit: in this doc, see §<section>.`** — when the ADR
  itself imports echo-types vocabulary structurally. Reserved for
  future ADRs that explicitly model rank-fusion / lossy summarisation;
  expected to be rare.

The existing two ADRs (`ADR-001-taxonomy.adoc`,
`ADR-002-stack-orchestrator-vs-fleet-mcp.adoc`) predate this directive
and are NOT required to be amended; they fall under "L1/L4 only,
not relevant".

## D. Concrete next actions

### D.1 Today: zero blocking actions

No cartridges-side proof, schema, or doc needs to change today. The audit
trail is:

* `cartridge.json` schema — no echo-types vocabulary needed.
* 111 of 112 `.idr` proofs — protocol-shape only, no echo-types
  obligation.
* 1 of 112 `.idr` proofs (local-coord-mcp) — already documents Phase 3
  echo-types obligations as deferred-upstream; no amendment needed.

### D.2 Watch items with documented trigger conditions

* **Watch item 1: local-coord-mcp Phase 3 unlock.** When Phase 2
  (P-15 choreographic types + P-16 epistemic types) lands upstream in
  echo-types or in the cartridge's own Idris2 layer, Phase 3 P-17 +
  P-18 unlock. At that moment, an upstream-echo-types-side sibling proof
  needs to be written (Agda; consumes `EchoChoreo`, `EchoEpistemic`,
  `EchoTropical`), and a forward-link added to
  `echo-types/docs/echo-types/cross-repo-bridge-status.md`. The
  cartridges-side `PROOF-SCHEDULE.adoc` should gain a "LANDED upstream
  YYYY-MM-DD" stamp on P-17 / P-18.
* **Watch item 2: codeseeker-mcp RRF fusion semantics.** If at any
  future point a downstream consumer asks for a semantic guarantee on
  RRF fused rankings (e.g. "the top-k under fusion is constrained by
  the union of per-ranker top-k under the following bound"), the
  natural home is an upstream-echo-types proof along the lines of
  `EchoTropical`'s argmin-with-residue. Trigger condition: someone files
  an issue against `codeseeker-mcp` asking "what does RRF guarantee?"
  Cartridges-side action: do NOT prove this in
  `SearchGraph.idr`; file an upstream issue against `hyperpolymath/echo-types`
  for an `EchoRankFusion` module + cite it back.
* **Watch item 3: kategoria-mcp / librarian-mcp ranking semantics.**
  Same pattern as Watch item 2; same trigger condition; same
  cartridges-side action (defer upstream). The four retrieval cartridges
  (codeseeker, kategoria, librarian, obsidian, zotero) collectively
  motivate a single upstream `EchoRankFusion` module rather than five
  per-cartridge proofs.

### D.3 Trigger conditions for re-audit of this document

This audit becomes stale and should be re-run when any of:

1. The cartridge.json schema gains a residue / loss / echo / fibre field
   at the top level. (Not expected.)
2. A new cartridge enters the repo whose primary value is rank-fusion,
   summarisation, or sampling, AND it ships a proof obligation. (Watch
   items 2 and 3 cover the existing latent cases; a NEW cartridge with
   active proofs would be a different trigger.)
3. Upstream echo-types ships `EchoRankFusion` (or equivalent). At that
   point the four retrieval cartridges become eligible consumers and a
   refresh of this audit should add forward-links.
4. The standing obligation
   `feedback_proofs_must_check_and_cross_doc_echo_types` is amended or
   superseded.

No calendar trigger. This is event-driven.

## E. References

* Upstream echo-types README:
  `/home/hyperpolymath/developer/repos/echo-types/README.md`
* Upstream echo-types EXPLAINME:
  `/home/hyperpolymath/developer/repos/echo-types/EXPLAINME.adoc`
* Upstream echo-types CLAUDE.md (ecosystem context + canonical-identity-suite
  status as of 2026-05-27): `/home/hyperpolymath/developer/repos/echo-types/CLAUDE.md`
* Cartridges-side echo-types reference:
  `/home/hyperpolymath/developer/repos/boj-server-cartridges/cartridges/cross-cutting/agentic/local-coord-mcp/abi/LocalCoord/PROOF-SCHEDULE.adoc`
* Standing obligation in memory:
  `~/.claude/projects/-home-hyperpolymath-developer-repos/memory/feedback_proofs_must_check_and_cross_doc_echo_types.md`

---

**Echo-types audit: closed (this is the cross-doc artifact).**
