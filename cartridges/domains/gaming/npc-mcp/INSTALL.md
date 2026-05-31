<!-- SPDX-License-Identifier: MPL-2.0 -->
# Installing npc-mcp

npc-mcp lives in the canonical cartridge repository under
`cartridges/domains/gaming/npc-mcp`. A BoJ host fetches it on demand; you need
only build its Zig core so the shared library is present for the host to load.

## Build the Zig FFI

```bash
cd cartridges/domains/gaming/npc-mcp/ffi
zig build              # produces zig-out/lib/libnpc_mcp.so
zig build test         # unit tests for the ABI and core modules
zig build integration  # synthetic JSONL stream through the core
```

The shared library is emitted at `ffi/zig-out/lib/libnpc_mcp.so`, the `so_path`
declared in `cartridge.json`. The host loads it through the standard
`boj_cartridge_invoke` ABI (ADR-0006); no per-cartridge adapter wiring exists.

## The Fabric mod and the wire protocol

The cartridge is only one half of the system. The companion Fabric mod and the
shared JSONL wire protocol live in the separate `npc-mcp` project. The mod dials
out to the host and drives this cartridge through its tools:

- it POSTs each protocol v1 event to `npc_ingest_event`;
- it polls `npc_drain_commands` and executes each returned command in-game.

Point the mod's connection config at the host's tool endpoint for this
cartridge. There is no inbound socket on the cartridge side.

## Persona

Command tools (`npc_say`, `npc_give`, `npc_execute_command`) are gated by the
active persona. Load one with `npc_load_persona`, passing the persona object as
the arguments. Until a persona is loaded, command tools fail closed; perception
reads remain available.

## Uninstall

Remove the cartridge directory from the tree; there is no host-side wiring to
reverse.
