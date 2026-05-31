<!-- SPDX-License-Identifier: MPL-2.0 -->
# librarian-mcp

A document RAG cartridge for BoJ. Hold books and long-form text on the server
and serve the most relevant passages to a model on demand. Nothing about the
retrieval needs to leave the machine: the index is a persistent, ownable set of
files on disk, and the brute-force cosine search runs in the Zig core.

## What it does

Given a document, the cartridge extracts its text, reflows it, splits it into
overlapping word-window chunks that remember which pages they span, embeds each
chunk, and stores the vectors alongside the chunk metadata. A query is embedded
the same way and matched against the stored vectors by cosine similarity; the
top passages are returned with their page references and scores.

## Architecture

Two layers, in the BoJ house pattern:

- `abi/Librarian/Protocol.idr` proves the protocol's safety properties: query,
  listing, and info are read-only and never denied; ingest and deletion are
  writes; no operation is both; and a collection name is path-safe, so no
  traversal name is representable.
- `ffi/` is the deterministic Zig core: extraction, cleaning, chunking,
  storage, and search. It makes no network calls; embeddings are injected. The
  core is reached through the standard `boj_cartridge_invoke` ABI (ADR-0006):
  the host marshals JSON to and from the tools and supplies embeddings. Under
  the `hash` backend the core computes offline vectors; under the `hf` backend
  the host delegates to `ml-mcp`'s HuggingFace feature-extraction.

### Embedding backends

- `hash`: a deterministic bag-of-hashed-words embedding computed in the core.
  Offline, dependency-free, and stable across runs (so persisted indices stay
  valid). Good for testing and for environments with no model access.
- `hf`: real semantic vectors from a HuggingFace feature-extraction model
  (default `BAAI/bge-small-en-v1.5`, 384 dimensions), obtained through the
  `ml-mcp` cartridge. The bge query-instruction prefix is applied to queries.

A collection records the backend and model it was built with; query embeddings
must match the stored dimensionality or the query is rejected.

## Storage

Each collection is a directory under `$BOJ_LIBRARIAN_HOME` (default
`$HOME/.local/share/boj/librarian/<name>/`):

- `vectors.bin` -- a small header (magic, dim, count) then row-major unit-norm
  f32 rows (host-endian; this is a local, ownable index).
- `chunks.json` -- the chunk metadata: id, text, page span, source.
- `meta.json` -- index parameters: dim, backend, model, chunk and page counts.

Writes are staged into a sibling directory and swapped into place, so a reader
never sees a half-written collection.

## Tools

Reads (never denied): `librarian_query`, `librarian_list_collections`,
`librarian_collection_info`.

Gated writes: `librarian_ingest`, `librarian_delete_collection`. Writes are
bounded by per-call limits (32 MiB per document, 100k chunks per ingest) and an
adapter switch.

## Page references

Page numbers are the document's PDF position, not the printed page number; the
printed numbers are offset by any front matter. Citations therefore name the
PDF page.

## Tests

The Zig core is test-driven end to end:

```
cd ffi
zig build test         # unit tests for every module
zig build integration  # build-then-query over a synthetic corpus, plus a full
                       # round trip through the C ABI, all on the offline hash
                       # backend (no network)
```
