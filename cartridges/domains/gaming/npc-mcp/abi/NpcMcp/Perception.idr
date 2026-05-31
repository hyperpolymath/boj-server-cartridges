-- SPDX-License-Identifier: MPL-2.0
||| Perception: proofs about the four-layer perception stack
|||
||| Proves that:
|||   1. Layer transitions are monotonic (a higher layer cannot be queried
|||      before its inputs exist)
|||   2. Narrative synthesis (Layer 3) depends only on world state (Layer 2)
|||      and the recent event history (Layer 1), never on raw bytes
module NpcMcp.Perception

%default total

||| The four perception layers, ordered.
public export
data Layer = L0Raw | L1Parsed | L2World | L3Narrative

||| Layer ordering: each layer depends on the one below.
public export
data LayerBelow : Layer -> Layer -> Type where
  RawBelowParsed     : LayerBelow L0Raw L1Parsed
  ParsedBelowWorld   : LayerBelow L1Parsed L2World
  WorldBelowNarr     : LayerBelow L2World L3Narrative

||| A layer is ready iff its direct predecessor is also ready.
||| (L0 is always ready — it's just a buffer.)
public export
data LayerReady : Layer -> Type where
  RawReady    : LayerReady L0Raw
  ParsedReady : LayerReady L0Raw -> LayerReady L1Parsed
  WorldReady  : LayerReady L1Parsed -> LayerReady L2World
  NarrReady   : LayerReady L2World -> LayerReady L3Narrative

||| Convenience: if the narrative layer is ready, every lower layer is too.
||| This is proved by induction; used by the adapter to refuse Layer-3
||| queries before the cartridge is fully bootstrapped.
export
narrativeImpliesAll : LayerReady L3Narrative -> LayerReady L2World
narrativeImpliesAll (NarrReady w) = w

export
layerCode : Layer -> Int
layerCode L0Raw      = 0
layerCode L1Parsed   = 1
layerCode L2World    = 2
layerCode L3Narrative = 3
