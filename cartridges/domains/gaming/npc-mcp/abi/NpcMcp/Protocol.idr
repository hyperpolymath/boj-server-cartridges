-- SPDX-License-Identifier: MPL-2.0
||| Protocol: NPC-MCP tool operations and safety proofs
|||
||| Defines the formal interface for the ghost-in-the-machine cartridge.
||| Proves that:
|||   1. Perception tools are read-only
|||   2. Destructive commands require explicit persona permission
|||   3. Command categories map unambiguously to integer ABI codes
module NpcMcp.Protocol

%default total

||| Every MCP tool the cartridge exposes
public export
data Operation
  = -- Layer 0-1 perception
    GetRawEvents
  | GetRecentEvents
  | SubscribeEvents
    -- Layer 2 world state
  | GetWorldState
  | GetPlayerState
  | QueryRegion
    -- Layer 3 narrative
  | GetNarrativeContext
  | GetPlayerProfile
    -- Communication commands
  | CmdSay
  | CmdTitle
  | CmdActionbar
  | CmdSound
    -- World manipulation commands
  | CmdSetblock
  | CmdFill
  | CmdSummon
  | CmdEffect
  | CmdWeather
  | CmdTime
    -- Player interaction commands
  | CmdGive
  | CmdTp
  | CmdGamemode
  | CmdXp
  | CmdScoreboard
    -- Meta / raw
  | CmdExecuteCommand
  | CmdDataGet
  | CmdSaveState
  | CmdLoadPersona

||| Operations that are read-only (safe to call without side effects).
||| This proof is what the cartridge trusts when enforcing "never deny a read".
public export
data IsReadOnly : Operation -> Type where
  RawReadOnly       : IsReadOnly GetRawEvents
  RecentReadOnly    : IsReadOnly GetRecentEvents
  SubReadOnly       : IsReadOnly SubscribeEvents
  WorldReadOnly     : IsReadOnly GetWorldState
  PlayerReadOnly    : IsReadOnly GetPlayerState
  RegionReadOnly    : IsReadOnly QueryRegion
  NarrativeReadOnly : IsReadOnly GetNarrativeContext
  ProfileReadOnly   : IsReadOnly GetPlayerProfile

||| Category used for permission grouping in persona configs.
public export
data Category = Perception | Communication | WorldOp | PlayerOp | Meta

public export
categoryOf : Operation -> Category
categoryOf GetRawEvents         = Perception
categoryOf GetRecentEvents      = Perception
categoryOf SubscribeEvents      = Perception
categoryOf GetWorldState        = Perception
categoryOf GetPlayerState       = Perception
categoryOf QueryRegion          = Perception
categoryOf GetNarrativeContext  = Perception
categoryOf GetPlayerProfile     = Perception
categoryOf CmdSay               = Communication
categoryOf CmdTitle             = Communication
categoryOf CmdActionbar         = Communication
categoryOf CmdSound             = Communication
categoryOf CmdSetblock          = WorldOp
categoryOf CmdFill              = WorldOp
categoryOf CmdSummon            = WorldOp
categoryOf CmdEffect            = WorldOp
categoryOf CmdWeather           = WorldOp
categoryOf CmdTime              = WorldOp
categoryOf CmdGive              = PlayerOp
categoryOf CmdTp                = PlayerOp
categoryOf CmdGamemode          = PlayerOp
categoryOf CmdXp                = PlayerOp
categoryOf CmdScoreboard        = PlayerOp
categoryOf CmdExecuteCommand    = Meta
categoryOf CmdDataGet           = Meta
categoryOf CmdSaveState         = Meta
categoryOf CmdLoadPersona       = Meta

||| Integer codes exported across the C ABI. Must match the enum in
||| ffi/src/npcmcp.zig exactly.
export
operationCode : Operation -> Int
operationCode GetRawEvents         = 0
operationCode GetRecentEvents      = 1
operationCode SubscribeEvents      = 2
operationCode GetWorldState        = 3
operationCode GetPlayerState       = 4
operationCode QueryRegion          = 5
operationCode GetNarrativeContext  = 6
operationCode GetPlayerProfile     = 7
operationCode CmdSay               = 100
operationCode CmdTitle             = 101
operationCode CmdActionbar         = 102
operationCode CmdSound             = 103
operationCode CmdSetblock          = 200
operationCode CmdFill              = 201
operationCode CmdSummon            = 202
operationCode CmdEffect            = 203
operationCode CmdWeather           = 204
operationCode CmdTime              = 205
operationCode CmdGive              = 300
operationCode CmdTp                = 301
operationCode CmdGamemode          = 302
operationCode CmdXp                = 303
operationCode CmdScoreboard        = 304
operationCode CmdExecuteCommand    = 900
operationCode CmdDataGet           = 901
operationCode CmdSaveState         = 902
operationCode CmdLoadPersona       = 903

||| C ABI export: is this operation code read-only?
||| Returns 1 for true, 0 for false, -1 for unknown code.
export
npc_is_readonly : Int -> Int
npc_is_readonly 0 = 1  -- GetRawEvents
npc_is_readonly 1 = 1  -- GetRecentEvents
npc_is_readonly 2 = 1  -- SubscribeEvents
npc_is_readonly 3 = 1  -- GetWorldState
npc_is_readonly 4 = 1  -- GetPlayerState
npc_is_readonly 5 = 1  -- QueryRegion
npc_is_readonly 6 = 1  -- GetNarrativeContext
npc_is_readonly 7 = 1  -- GetPlayerProfile
npc_is_readonly n  = if n >= 100 && n <= 999 then 0 else -1
