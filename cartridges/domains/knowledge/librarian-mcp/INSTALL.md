<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
# Installing librarian-mcp

librarian-mcp lives in the canonical cartridge repository under
`cartridges/domains/knowledge/librarian-mcp`. A BoJ host (boj-server, panll)
fetches it on demand; you need only build its Zig core so the shared library is
present for the host to load.

## Build the Zig FFI

```bash
cd cartridges/domains/knowledge/librarian-mcp/ffi
zig build              # produces zig-out/lib/liblibrarian_mcp.so and the static lib
zig build test         # unit tests
zig build integration  # end-to-end and C-ABI round trip (offline hash backend)
```

The shared library is emitted at
`ffi/zig-out/lib/liblibrarian_mcp.so`, the `so_path` declared in
`cartridge.json`. The host loads it through the standard `boj_cartridge_invoke`
ABI (ADR-0006); no per-cartridge adapter wiring is required.

## Embedding delegation

The `hf` backend obtains real semantic vectors from the `ml-mcp` cartridge's
HuggingFace feature-extraction; build that cartridge if you intend to use it:

```bash
cd ../../../cross-cutting/.../ml-mcp/ffi && zig build   # adjust to ml-mcp's path in this tree
```

HuggingFace credentials are reused from `ml-mcp` (set its token as that
cartridge documents). The `hash` backend needs none of this and runs offline,
which is what the integration test exercises.

## Invoke through the host

Once the host has loaded the cartridge, the tools are reached through its invoke
envelope, `{"tool":"...","args":"..."}`, where `args` is itself a JSON string:

```bash
# Ingest (offline hash backend; use "hf" for HuggingFace via ml-mcp):
curl -X POST http://localhost:7700/cartridge/librarian-mcp/invoke \
  -H 'Content-Type: application/json' \
  -d '{"tool":"librarian_ingest","args":"{\"collection\":\"book\",\"source_name\":\"book.pdf\",\"pdf_path\":\"/abs/book.pdf\",\"backend\":\"hash\"}"}'

# Query:
curl -X POST http://localhost:7700/cartridge/librarian-mcp/invoke \
  -H 'Content-Type: application/json' \
  -d '{"tool":"librarian_query","args":"{\"collection\":\"book\",\"query\":\"...\",\"k\":5}"}'
```

The exact host route and port depend on the host's configuration; the envelope
shape is what the cartridge guarantees.

## Configuration

- `BOJ_LIBRARIAN_HOME` -- collections root on disk. Defaults to
  `$HOME/.local/share/boj/librarian`. The Zig core never reads the environment
  itself (when loaded as a shared library from a non-Zig host, `std.os.environ`
  is unset); the host resolves this path and passes it to `librarian_init`.
- `BOJ_LIBRARIAN_READONLY` -- if set to any value, ingest and delete are
  refused (reads remain available).

## Uninstall

Remove the cartridge directory from the tree; there is no host-side wiring to
reverse.
