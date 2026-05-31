// SPDX-License-Identifier: MPL-2.0
//
// Orchestration: thread extraction, cleaning, chunking, embedding, storage, and
// search together. Embeddings are injected (the host supplies real vectors
// from ml-mcp under the "hf" backend); the deterministic "hash" backend lets
// the whole pipeline run and be tested offline. Reads never fail on a missing
// collection: they return an empty result. Writes are gated by slug validation
// and per-call size limits.

const std = @import("std");
const clean = @import("clean.zig");
const chunk = @import("chunk.zig");
const embed = @import("embed.zig");
const search = @import("search.zig");
const store = @import("store.zig");
const extract = @import("extract.zig");

pub const Error = error{ NoSource, DimMismatch, TooLarge, CountMismatch };

/// Per-call write limits, bounding the model-facing write surface.
pub const max_document_bytes: usize = 32 * 1024 * 1024;
pub const max_chunks_per_ingest: usize = 100_000;

pub const IngestOptions = struct {
    text: ?[]const u8 = null,
    pdf_path: ?[]const u8 = null,
    chunk_words: usize = 220,
    overlap: usize = 45,
};

pub const Extracted = struct {
    pages: usize,
    set: chunk.ChunkSet,

    pub fn deinit(self: *Extracted) void {
        self.set.deinit();
    }
};

pub const QueryHit = struct {
    score: f32,
    page_start: usize,
    page_end: usize,
    source: []u8,
    text: []u8,
};

pub const QueryResult = struct {
    allocator: std.mem.Allocator,
    hits: []QueryHit,

    pub fn deinit(self: *QueryResult) void {
        for (self.hits) |h| {
            self.allocator.free(h.source);
            self.allocator.free(h.text);
        }
        self.allocator.free(self.hits);
    }
};

/// Extract a document into pages, then chunk it. The caller embeds the chunks.
pub fn extractAndChunk(allocator: std.mem.Allocator, opts: IngestOptions) !Extracted {
    var pages: [][]u8 = undefined;
    if (opts.text) |t| {
        if (t.len > max_document_bytes) return Error.TooLarge;
        pages = try extract.pagesFromText(allocator, t);
    } else if (opts.pdf_path) |p| {
        pages = try extract.extractPdf(allocator, p);
    } else {
        return Error.NoSource;
    }
    defer extract.freePages(allocator, pages);

    var total: usize = 0;
    for (pages) |p| total += p.len;
    if (total > max_document_bytes) return Error.TooLarge;

    // Present the mutable pages as the const view chunkPages expects.
    const view = try allocator.alloc([]const u8, pages.len);
    defer allocator.free(view);
    for (pages, 0..) |p, i| view[i] = p;

    var set = try chunk.chunkPages(allocator, view, opts.chunk_words, opts.overlap);
    if (set.chunks.len > max_chunks_per_ingest) {
        set.deinit();
        return Error.TooLarge;
    }
    return Extracted{ .pages = pages.len, .set = set };
}

/// Hash-embed every chunk into a flattened, row-major vector buffer of
/// count * embed.hash_dim. The caller owns the slice.
pub fn hashEmbedChunks(allocator: std.mem.Allocator, set: chunk.ChunkSet) ![]f32 {
    const dim = embed.hash_dim;
    const out = try allocator.alloc(f32, set.chunks.len * dim);
    errdefer allocator.free(out);
    for (set.chunks, 0..) |c, i| {
        const v = try embed.hashEmbed(allocator, c.text);
        defer allocator.free(v);
        @memcpy(out[i * dim ..][0..dim], v);
    }
    return out;
}

pub const CommitParams = struct {
    name: []const u8,
    source: []const u8,
    backend: []const u8,
    model: []const u8,
    chunk_words: usize,
    overlap: usize,
    pages: usize,
    dim: usize,
    set: chunk.ChunkSet,
    vectors: []const f32,
};

/// Persist a collection from chunk texts and their parallel vectors.
pub fn commit(allocator: std.mem.Allocator, root_dir: std.fs.Dir, params: CommitParams) !usize {
    const count = params.set.chunks.len;
    if (params.vectors.len != count * params.dim) return Error.CountMismatch;

    var stored = try allocator.alloc(store.StoredChunk, count);
    defer allocator.free(stored);
    for (params.set.chunks, 0..) |c, i| {
        stored[i] = store.StoredChunk{
            .id = c.id,
            .text = c.text,
            .page_start = c.page_start,
            .page_end = c.page_end,
            .source = params.source,
        };
    }

    const col = store.Collection{
        .allocator = allocator,
        .dim = params.dim,
        .chunk_words = params.chunk_words,
        .overlap = params.overlap,
        .pages = params.pages,
        .backend = params.backend,
        .model = params.model,
        .vectors = @constCast(params.vectors),
        .chunks = stored,
    };
    try store.saveTo(allocator, root_dir, params.name, col);
    return count;
}

/// Query a collection. A missing collection yields an empty result rather than
/// an error, honouring "reads are never denied".
pub fn query(
    allocator: std.mem.Allocator,
    root_dir: std.fs.Dir,
    name: []const u8,
    query_vec: []const f32,
    k: usize,
) !QueryResult {
    const empty = QueryResult{ .allocator = allocator, .hits = try allocator.alloc(QueryHit, 0) };
    var col = store.loadFrom(allocator, root_dir, name) catch |e| switch (e) {
        store.Error.CollectionNotFound, store.Error.InvalidName => return empty,
        else => return e,
    };
    defer col.deinit();

    if (query_vec.len != col.dim) {
        allocator.free(empty.hits);
        return Error.DimMismatch;
    }

    const raw = try search.topK(allocator, col.vectors, col.dim, query_vec, k);
    defer allocator.free(raw);
    allocator.free(empty.hits);

    var hits = try allocator.alloc(QueryHit, raw.len);
    var filled: usize = 0;
    errdefer {
        for (hits[0..filled]) |h| {
            allocator.free(h.source);
            allocator.free(h.text);
        }
        allocator.free(hits);
    }
    for (raw, 0..) |hit, i| {
        const c = col.chunks[hit.index];
        hits[i] = QueryHit{
            .score = hit.score,
            .page_start = c.page_start,
            .page_end = c.page_end,
            .source = try allocator.dupe(u8, c.source),
            .text = try allocator.dupe(u8, c.text),
        };
        filled = i + 1;
    }
    return QueryResult{ .allocator = allocator, .hits = hits };
}

test "query of a missing collection returns an empty result" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const qv = [_]f32{ 1.0, 0.0 };
    var res = try query(std.testing.allocator, tmp.dir, "ghost", &qv, 5);
    defer res.deinit();
    try std.testing.expectEqual(@as(usize, 0), res.hits.len);
}
