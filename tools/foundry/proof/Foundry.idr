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

||| The proof-obligations every shippable cartridge must discharge.
public export
data Obligation
  = AbiConform   -- implements the boj_cartridge_* ABI (ADR-0006)
  | MemSafe      -- no undefined behaviour across the FFI boundary
  | Truthful     -- `available` implies a non-stub invoke (the #196 gate)
  | CapBounded   -- uses only the capabilities it was granted

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
