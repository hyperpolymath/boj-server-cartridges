<!-- SPDX-License-Identifier: MPL-2.0 -->
# npc-mcp

A BoJ cartridge that embeds an AI presence, a "ghost in the machine", inside a
Minecraft server. The cartridge holds a layered perception of the game world and
exposes curated command tools so an MCP client can act as an unseen participant.

## Transport

The cartridge holds no socket of its own. A companion Fabric mod (in the
separate `npc-mcp` project, alongside the shared JSONL wire protocol) dials out
to the host and drives the cartridge through ordinary tool calls:

- it POSTs each world event to `npc_ingest_event`;
- it polls `npc_drain_commands` for queued actions and executes them in-game.

So the cartridge is a passive request/response state machine: events in,
commands out. Nothing here listens on a port.

## Architecture

Two layers, in the BoJ house pattern:

- `abi/NpcMcp/*.idr` proves the protocol's safety properties: perception is
  read-only, command tools are persona-gated, and state transitions are total.
- `ffi/` is the Zig core: a ring buffer of raw events, a world-state model, a
  narrative synthesiser, a rate-limited command queue, and the persona gate.
  `npc_mcp_ffi.zig` exposes the standard `boj_cartridge_invoke` ABI (ADR-0006)
  over that core.

## Tools

Perception (read-only): `npc_get_narrative_context`, `npc_get_world_state`,
`npc_get_recent_events`.

Transport (driven by the mod): `npc_ingest_event`, `npc_drain_commands`.

Commands (persona-gated; queued for the mod): `npc_say`, `npc_give`,
`npc_execute_command`. Plus `npc_load_persona` to set the active persona; until
one is loaded, command tools fail closed.

## Tests

```
cd ffi
zig build test         # unit tests for the ABI and every core module
zig build integration  # a synthetic JSONL event stream through the core
```
