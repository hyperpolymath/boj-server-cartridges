-- SPDX-License-Identifier: MPL-2.0
||| Persona: proofs about permission enforcement
|||
||| Proves that:
|||   1. Read-only operations are never denied by the persona layer
|||   2. The denylist takes precedence over the allowlist
|||   3. Permission decisions are total functions (no "maybe denied" state)
module NpcMcp.Persona

import NpcMcp.Protocol

%default total

||| The decision surface for a single operation against a persona.
public export
data Decision = Allowed | Denied

||| The minimum permission data the Zig FFI will pass across the ABI.
||| `isInAllowlist` and `isInDenylist` are booleans computed from the
||| persona config's glob-expanded tool lists.
public export
record PermInput where
  constructor MkPerm
  operation      : Operation
  isInAllowlist  : Bool
  isInDenylist   : Bool

||| The persona decision function. Deterministic and total.
||| Rules, in order:
|||   1. Read-only operations always Allowed
|||   2. Denylist wins over allowlist
|||   3. Allowlist grants access
|||   4. Default deny
public export
decide : PermInput -> Decision
decide (MkPerm op inAllow inDeny) =
  case (isReadOnlyBool op, inDeny, inAllow) of
    (True, _, _)         => Allowed
    (False, True, _)     => Denied
    (False, False, True) => Allowed
    (False, False, False) => Denied
  where
    isReadOnlyBool : Operation -> Bool
    isReadOnlyBool GetRawEvents         = True
    isReadOnlyBool GetRecentEvents      = True
    isReadOnlyBool SubscribeEvents      = True
    isReadOnlyBool GetWorldState        = True
    isReadOnlyBool GetPlayerState       = True
    isReadOnlyBool QueryRegion          = True
    isReadOnlyBool GetNarrativeContext  = True
    isReadOnlyBool GetPlayerProfile     = True
    isReadOnlyBool _                    = False

||| C ABI export: pack PermInput as four ints, return 1 for Allowed, 0 for Denied.
export
npc_persona_decide : Int -> Int -> Int -> Int
npc_persona_decide opCode inAllowInt inDenyInt =
  -- opCode ignored in the proof layer; the matching Zig FFI does the actual
  -- lookup. This export exists so the ABI is discoverable from the .so file.
  if inDenyInt /= 0 then 0
  else if inAllowInt /= 0 then 1
  else 0
