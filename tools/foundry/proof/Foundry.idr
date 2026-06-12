-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
-- Foundry — assurance model for the cartridge-making pipeline.
--
-- This module is a PROOF OF DESIGN, not runtime code. It models the
-- mint -> provision -> configure -> harness flow at the type level so the
-- Idris2 checker mechanically guarantees two properties the hand-written
-- wizard (foundry.sh) must honour:
--
--   (1) NO DROPPED PROOFS. Every stage is a total function whose result type
--       carries at least the proof-obligations its input carried. A cartridge
--       can be SEALED only once ALL required obligations are present in its
--       type. Skip a stage and an obligation stays undischarged -> it does not
--       compile. The `failing` block below is that guarantee, machine-checked.
--
--   (2) LEAST AUTHORITY. An artifact is indexed by the EXACT capability set it
--       was provisioned with; later stages preserve that index and there is no
--       operation that widens it. A cartridge can hold no capability beyond its
--       grant. This is the near-term, type-level form of the "maximal principal
--       reduction / provable inertness" horizon (issue #d).

module Foundry

import Data.List.Elem

%default total

------------------------------------------------------------------------
-- Proof obligations and capabilities
------------------------------------------------------------------------

||| The proof-obligations a cartridge can discharge. The first four are the BASE
||| bundle every shippable cartridge must carry; the last three are BEHAVIOURAL,
||| added per kind (see `extra`). They share one index so the base proofs are
||| untouched and a kind simply requires a longer obligation set.
public export
data Obligation
  = AbiConform      -- implements the boj_cartridge_* ABI (ADR-0006)
  | MemSafe         -- no undefined behaviour across the FFI boundary
  | Truthful        -- `available` implies a non-stub invoke (the #196 gate)
  | CapBounded      -- uses only the capabilities it was granted
  | RoutingSound    -- coordination: a request reaches exactly one correct downstream
  | ExecCapBounded  -- agentic: each execution step uses only granted capabilities
  | SymbolicSound   -- nesy: the neural->symbolic bridge preserves declared invariants

||| Capabilities the general harness can grant. Anything not granted is denied.
public export
data Capability = Net | Fs | Cred | Clock | Rand

------------------------------------------------------------------------
-- The artifact, indexed by discharged obligations and granted capabilities
------------------------------------------------------------------------

||| A cartridge under construction. The two type indices ARE the assurance:
||| `discharged` is the set of obligations already met; `caps` is the exact
||| capability grant. Both live in the type, so the checker tracks them and the
||| value-level payload (here just `name`) can never contradict them.
public export
record Artifact (discharged : List Obligation) (caps : List Capability) where
  constructor MkArtifact
  name : String

------------------------------------------------------------------------
-- Stages — each total, each preserves or extends `discharged`
------------------------------------------------------------------------

||| MINT. Scaffolds from the proven template, so the fresh artifact already
||| carries ABI-conformance and memory-safety — inherited from the framework,
||| never re-derived. No capabilities yet.
export
mint : (name : String) -> Artifact [AbiConform, MemSafe] []
mint name = MkArtifact name

||| PROVISION. Grants exactly `granted` and discharges CapBounded. The result is
||| indexed by `granted`: the artifact can hold no capability outside it.
export
provision : (granted : List Capability)
         -> Artifact ds caps
         -> Artifact (CapBounded :: ds) granted
provision granted (MkArtifact n) = MkArtifact n

||| CONFIGURE. Applies settings. PRESERVES both indices — it can neither drop a
||| discharged obligation nor widen the capability grant.
export
configure : (String -> String)
         -> Artifact ds caps
         -> Artifact ds caps
configure f (MkArtifact n) = MkArtifact (f n)

||| HARNESS. Runs the standard harness (truthfulness probe + ABI proof check)
||| and discharges Truthful. Preserves capabilities.
export
harness : Artifact ds caps -> Artifact (Truthful :: ds) caps
harness (MkArtifact n) = MkArtifact n

------------------------------------------------------------------------
-- Completeness: a sealed cartridge must carry ALL required obligations
------------------------------------------------------------------------

public export
RequiredObligations : List Obligation
RequiredObligations = [AbiConform, MemSafe, Truthful, CapBounded]

||| Evidence that every required obligation has been discharged in `ds`. Each
||| field is an `Elem` proof the checker finds automatically for a concrete
||| `ds`; if any obligation is missing, no value of this type exists.
public export
data Complete : (ds : List Obligation) -> Type where
  MkComplete :  {auto p1 : Elem AbiConform ds}
             -> {auto p2 : Elem MemSafe ds}
             -> {auto p3 : Elem Truthful ds}
             -> {auto p4 : Elem CapBounded ds}
             -> Complete ds

||| A sealed, shippable cartridge. Unconstructable unless `Complete ds` holds —
||| i.e. unless every stage ran and discharged its obligation.
public export
record Sealed where
  constructor Seal
  {0 ds   : List Obligation}
  {0 caps : List Capability}
  artifact : Artifact ds caps
  0 complete : Complete ds

------------------------------------------------------------------------
-- The pipeline — and the proof it always yields a complete cartridge
------------------------------------------------------------------------

||| The whole flow. That this typechecks IS the assurance: the result is
||| `Sealed`, unconstructable without `Complete`, and `Complete` holds here only
||| because mint + provision + harness each discharged their part.
export
foundry : (name : String) -> (granted : List Capability) -> Sealed
foundry name granted =
  let a1 = mint name
      a2 = provision granted a1
      a3 = configure id a2
      a4 = harness a3
   in Seal a4 MkComplete

------------------------------------------------------------------------
-- Machine-checked guarantees
------------------------------------------------------------------------

-- NO DROPPED PROOFS, asserted negatively. A pipeline that SKIPS the harness
-- never discharges `Truthful`, so `Complete` has no value and sealing does not
-- typecheck. The `failing` block asserts exactly that compile error — so if a
-- future refactor accidentally made proof-dropping seal-able, THIS file would
-- stop compiling.
failing "Can't find an implementation for Elem Truthful"
  droppedProofIsRejected : (name : String) -> Sealed
  droppedProofIsRejected name = Seal (provision [] (mint name)) MkComplete

||| LEAST AUTHORITY, witnessed by the type. An artifact provisioned with [Fs]
||| has capability index exactly [Fs], and the later stages preserve it. If any
||| stage widened the grant, these signatures would not hold.
export
boundedToFs : Artifact [Truthful, CapBounded, AbiConform, MemSafe] [Fs]
boundedToFs = harness (configure id (provision [Fs] (mint "demo")))

------------------------------------------------------------------------
-- Capability partition — the value-level CapBounded that provision.sh emits
------------------------------------------------------------------------
-- The operational Provision stage (stages/provision.sh) writes a `capabilities`
-- block that PARTITIONS a fixed universe into `ephemeral` (granted) and
-- `locked_down` (denied = universe \ granted). This section models that
-- partition in the same proof assistant, so the shell stage and the design
-- proof cannot drift: the same partition law is stated here and machine-checked.

||| Structural equality on capabilities, needed to compute set difference.
public export
Eq Capability where
  Net == Net = True; Fs == Fs = True; Cred == Cred = True
  Clock == Clock = True; Rand == Rand = True
  _ == _ = False

||| The framework-fixed capability universe — identical to foundry.sh `CAPS` and
||| provision.sh's default universe.
public export
universe : List Capability
universe = [Net, Fs, Cred, Clock, Rand]

||| Locked-down = universe minus the grant. Under fork-per-request (ADR-0005)
||| every grant is ephemeral, so a capability is either granted (ephemeral) or
||| locked-down — never both, and nothing escapes the universe. Mirrors exactly
||| `locked_down = universe \ ephemeral` in provision.sh.
public export
lockedDown : (granted : List Capability) -> List Capability
lockedDown granted = filter (\c => not (c `elem` granted)) universe

||| INERTNESS EXTREMES, machine-checked by reduction. Granting nothing locks the
||| ENTIRE universe — the maximally-inert / obleeny limit (inertness = 1.0 in
||| provision.sh). Granting everything locks nothing (inertness = 0.0).
public export
grantNothingLocksAll : lockedDown [] = Foundry.universe
grantNothingLocksAll = Refl

public export
grantAllLocksNothing : lockedDown Foundry.universe = []
grantAllLocksNothing = Refl

||| A representative interior point: granting [Fs] locks down exactly the other
||| four (here in universe order; provision.sh emits the same SET sorted, with
||| inertness 4/5 = 0.8 — asserted in test/test-foundry.sh).
public export
grantFsLocksRest : lockedDown [Fs] = [Net, Cred, Clock, Rand]
grantFsLocksRest = Refl

------------------------------------------------------------------------
-- Extensibility — per-kind obligation bundles (issue #37)
------------------------------------------------------------------------
-- A cartridge KIND is the base bundle PLUS the behavioural obligations its
-- harness enforces. The Foundry is parameterised over kind, so new server
-- classes plug in WITHOUT touching the flow: a kind only ADDS obligations, and
-- the per-kind harness discharges exactly those. An `agentic` cartridge is then
-- BORN carrying the agentic proof — the "proven pre-mint framework" the SPEC
-- describes, here machine-checked. The behavioural obligations join the same
-- `discharged` index as the base ones, so all the proofs above are unaffected.

||| The server kinds the maker can compose. `Domain` is the common case (base
||| bundle only); the rest are the cross-cutting kinds (issue #37).
public export
data Kind = Domain | Coordination | Agentic | Nesy

||| The extra obligation(s) each kind carries beyond the base bundle.
public export
extra : Kind -> List Obligation
extra Domain       = []
extra Coordination = [RoutingSound]
extra Agentic      = [ExecCapBounded]
extra Nesy         = [SymbolicSound]

||| PER-KIND HARNESS — the one general harness, specialised to a kind. It runs the
||| base harness (discharging Truthful) AND discharges exactly the kind's extra
||| obligations: never fewer (no dropped proofs), never more (least authority at
||| the obligation level). For `Domain`, `extra` is empty, so it is precisely the
||| base harness.
export
harnessFor : {0 ds : List Obligation} -> {0 caps : List Capability}
          -> (k : Kind) -> Artifact ds caps -> Artifact (extra k ++ Truthful :: ds) caps
harnessFor _ (MkArtifact n) = MkArtifact n

||| Per-kind completeness: the base bundle is `Complete` AND every obligation the
||| kind requires is discharged. Built from the existing `Complete` plus one
||| `Elem` per kind — the same auto-`Elem` pattern proven above.
public export
data CompleteFor : (k : Kind) -> (ds : List Obligation) -> Type where
  DomainOK  : {0 ds : List Obligation} -> {auto base : Complete ds}
           -> CompleteFor Domain ds
  CoordOK   : {0 ds : List Obligation} -> {auto base : Complete ds}
           -> {auto r : Elem RoutingSound ds} -> CompleteFor Coordination ds
  AgenticOK : {0 ds : List Obligation} -> {auto base : Complete ds}
           -> {auto r : Elem ExecCapBounded ds} -> CompleteFor Agentic ds
  NesyOK    : {0 ds : List Obligation} -> {auto base : Complete ds}
           -> {auto r : Elem SymbolicSound ds} -> CompleteFor Nesy ds

||| A sealed cartridge OF A KIND — unconstructable unless the kind's FULL
||| obligation bundle (base + behavioural) is present in its type.
public export
record SealedFor (k : Kind) where
  constructor SealK
  {0 ds   : List Obligation}
  {0 caps : List Capability}
  artifact : Artifact ds caps
  0 complete : CompleteFor k ds

||| The kinded flow. Mint+provision+configure as before, then the kind's harness.
||| That every branch typechecks IS the per-kind assurance: the agentic flow
||| seals an agentic cartridge precisely because `harnessFor Agentic` discharged
||| `ExecCapBounded`. The branches share one body and differ only in the
||| completeness witness the checker must find.
export
foundryFor : (k : Kind) -> (name : String) -> (granted : List Capability) -> SealedFor k
foundryFor Domain       n g = SealK (harnessFor Domain       (configure id (provision g (mint n)))) DomainOK
foundryFor Coordination n g = SealK (harnessFor Coordination (configure id (provision g (mint n)))) CoordOK
foundryFor Agentic      n g = SealK (harnessFor Agentic      (configure id (provision g (mint n)))) AgenticOK
foundryFor Nesy         n g = SealK (harnessFor Nesy         (configure id (provision g (mint n)))) NesyOK

||| Positive witness: the agentic flow DOES seal an agentic cartridge — it
||| carries `ExecCapBounded` because `harnessFor Agentic` discharged it. (The
||| companion `failing` block below shows the base harness does not.)
public export
agenticSeals : SealedFor Agentic
agenticSeals = foundryFor Agentic "demo-agentic" [Fs]

-- NO DROPPED PROOFS, per kind. An agentic cartridge run through the BASE
-- (Domain) harness never discharges `ExecCapBounded`, so it cannot seal AS
-- agentic. This `failing` block pins that exact compile error — if a refactor
-- ever let an agentic cartridge seal without its obligation, THIS file would
-- stop compiling.
failing "Can't find an implementation for Elem ExecCapBounded"
  agenticNeedsItsProof : (name : String) -> SealedFor Agentic
  agenticNeedsItsProof name =
    SealK (harnessFor Domain (configure id (provision [] (mint name)))) AgenticOK
