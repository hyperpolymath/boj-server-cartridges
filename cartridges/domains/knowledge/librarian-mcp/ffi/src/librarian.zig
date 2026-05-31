// SPDX-License-Identifier: MPL-2.0
//
// librarian-mcp Cartridge - Zig FFI core.
//
// Holds documents on BoJ and serves relevant passages to models. This root
// module wires the deterministic pipeline (extract, clean, chunk, store,
// search) together and exposes the C ABI. Embeddings are injected by the
// host; the core never makes a network call. Every export takes and
// returns JSON (or an i32 status); strings are returned via allocSentinel and
// reclaimed by librarian_free_string.

const std = @import("std");

pub const clean = @import("clean.zig");
pub const chunk = @import("chunk.zig");
pub const embed = @import("embed.zig");
pub const search = @import("search.zig");
pub const store = @import("store.zig");
pub const extract = @import("extract.zig");
pub const pipeline = @import("pipeline.zig");

// ── Global state ──

// Zig 0.15.2: std.heap.GeneralPurposeAllocator was removed; use DebugAllocator.
var g_allocator: std.heap.DebugAllocator(.{}) = .init;

const State = struct {
    allocator: std.mem.Allocator,
    root: std.fs.Dir,
};

var g_state: ?State = null;

// ── Lifecycle ──

/// Initialise the cartridge with a collections root. The caller (the host)
/// is expected to pass an explicit absolute path; a zero-length path uses a
/// relative default. The core deliberately does not read the environment:
/// loaded as a shared library from a non-Zig host, std.os.environ is never set
/// up by a Zig start routine, so any environment access would fault. Path
/// resolution from $BOJ_LIBRARIAN_HOME / $HOME belongs in the host.
pub export fn librarian_init(root_ptr: [*]const u8, root_len: usize) callconv(.c) i32 {
    if (g_state != null) return 0;
    const a = g_allocator.allocator();

    const path: []const u8 = if (root_len > 0) root_ptr[0..root_len] else "boj-librarian";

    std.fs.cwd().makePath(path) catch return -3;
    const dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return -4;
    g_state = State{ .allocator = a, .root = dir };
    return 0;
}

pub export fn librarian_shutdown() callconv(.c) i32 {
    if (g_state) |*s| {
        s.root.close();
        g_state = null;
    }
    _ = g_allocator.deinit();
    return 0;
}

pub export fn librarian_free_string(s: [*:0]const u8) callconv(.c) void {
    const st = g_state orelse return;
    const slice = std.mem.span(s);
    st.allocator.free(slice);
}

// ── JSON helpers ──

fn jsonOwned(a: std.mem.Allocator, value: anytype) ![*:0]const u8 {
    var w = std.Io.Writer.Allocating.init(a);
    defer w.deinit();
    try std.json.Stringify.value(value, .{}, &w.writer);
    const bytes = w.written();
    const out = try a.allocSentinel(u8, bytes.len, 0);
    @memcpy(out, bytes);
    return out;
}

const parse_opts = std.json.ParseOptions{ .ignore_unknown_fields = true };

// ── Request and response shapes ──

const ChunkReq = struct {
    text: ?[]const u8 = null,
    pdf_path: ?[]const u8 = null,
    chunk_words: usize = 220,
    overlap: usize = 45,
};

const ChunkOut = struct {
    id: usize,
    text: []const u8,
    page_start: usize,
    page_end: usize,
};

const ChunkResp = struct {
    pages: usize,
    chunks: []ChunkOut,
};

const CommitReq = struct {
    collection: []const u8,
    source: []const u8,
    backend: []const u8 = "hf",
    model: []const u8 = "",
    chunk_words: usize = 220,
    overlap: usize = 45,
    pages: usize = 0,
    dim: usize,
    chunks: []ChunkOut,
    vectors: [][]f32,
};

const CommitResp = struct {
    collection: []const u8,
    chunks_added: usize,
    dim: usize,
};

const QueryReq = struct {
    collection: []const u8,
    query_vector: []f32,
    k: usize = 5,
};

const QueryOut = struct {
    score: f32,
    page_start: usize,
    page_end: usize,
    source: []const u8,
    text: []const u8,
};

const InfoOut = struct {
    name: []const u8,
    source: []const u8,
    backend: []const u8,
    model: []const u8,
    dim: usize,
    chunks: usize,
    pages: usize,
};

// ── Exports ──

/// Embed text with the offline hash backend. Returns {"dim":N,"vector":[...]}.
pub export fn librarian_hash_embed(text_ptr: [*]const u8, text_len: usize) callconv(.c) [*:0]const u8 {
    const st = g_state orelse return errJson("not initialised");
    const a = st.allocator;
    const v = embed.hashEmbed(a, text_ptr[0..text_len]) catch return errJson("embed failed");
    defer a.free(v);
    return jsonOwned(a, .{ .dim = embed.hash_dim, .vector = v }) catch errJson("oom");
}

/// Extract and chunk a document. Returns {"pages":N,"chunks":[...]}.
pub export fn librarian_chunk(req_ptr: [*]const u8, req_len: usize) callconv(.c) [*:0]const u8 {
    const st = g_state orelse return errJson("not initialised");
    const a = st.allocator;
    const parsed = std.json.parseFromSlice(ChunkReq, a, req_ptr[0..req_len], parse_opts) catch return errJson("bad request");
    defer parsed.deinit();
    const r = parsed.value;

    var extracted = pipeline.extractAndChunk(a, .{
        .text = r.text,
        .pdf_path = r.pdf_path,
        .chunk_words = r.chunk_words,
        .overlap = r.overlap,
    }) catch |e| return errJsonDyn(a, @errorName(e));
    defer extracted.deinit();

    const outs = a.alloc(ChunkOut, extracted.set.chunks.len) catch return errJson("oom");
    defer a.free(outs);
    for (extracted.set.chunks, 0..) |c, i| {
        outs[i] = ChunkOut{ .id = c.id, .text = c.text, .page_start = c.page_start, .page_end = c.page_end };
    }
    return jsonOwned(a, ChunkResp{ .pages = extracted.pages, .chunks = outs }) catch errJson("oom");
}

/// Persist a collection from chunks and their parallel vectors.
pub export fn librarian_commit(req_ptr: [*]const u8, req_len: usize) callconv(.c) [*:0]const u8 {
    const st = g_state orelse return errJson("not initialised");
    const a = st.allocator;
    const parsed = std.json.parseFromSlice(CommitReq, a, req_ptr[0..req_len], parse_opts) catch return errJson("bad request");
    defer parsed.deinit();
    const r = parsed.value;

    if (r.vectors.len != r.chunks.len) return errJson("CountMismatch");
    const flat = a.alloc(f32, r.chunks.len * r.dim) catch return errJson("oom");
    defer a.free(flat);
    for (r.vectors, 0..) |row, i| {
        if (row.len != r.dim) return errJson("DimMismatch");
        @memcpy(flat[i * r.dim ..][0..r.dim], row);
    }

    // Rebuild a ChunkSet the tested pipeline can consume. On a mid-loop
    // allocation failure, free exactly what was filled plus the backing slice,
    // since a truncated ChunkSet would mis-free the original allocation.
    const chunks = a.alloc(chunk.Chunk, r.chunks.len) catch return errJson("oom");
    var filled: usize = 0;
    var ok = true;
    for (r.chunks, 0..) |c, i| {
        chunks[i] = chunk.Chunk{
            .id = c.id,
            .text = a.dupe(u8, c.text) catch {
                ok = false;
                break;
            },
            .page_start = c.page_start,
            .page_end = c.page_end,
        };
        filled = i + 1;
    }
    if (!ok) {
        for (chunks[0..filled]) |cc| a.free(cc.text);
        a.free(chunks);
        return errJson("oom");
    }
    var set = chunk.ChunkSet{ .chunks = chunks, .allocator = a };
    defer set.deinit();

    const added = pipeline.commit(a, st.root, .{
        .name = r.collection,
        .source = r.source,
        .backend = r.backend,
        .model = r.model,
        .chunk_words = r.chunk_words,
        .overlap = r.overlap,
        .pages = r.pages,
        .dim = r.dim,
        .set = set,
        .vectors = flat,
    }) catch |e| return errJsonDyn(a, @errorName(e));

    return jsonOwned(a, CommitResp{ .collection = r.collection, .chunks_added = added, .dim = r.dim }) catch errJson("oom");
}

/// Query a collection. Returns a JSON array of hits, or [] when absent.
pub export fn librarian_query(req_ptr: [*]const u8, req_len: usize) callconv(.c) [*:0]const u8 {
    const st = g_state orelse return errJson("not initialised");
    const a = st.allocator;
    const parsed = std.json.parseFromSlice(QueryReq, a, req_ptr[0..req_len], parse_opts) catch return errJson("bad request");
    defer parsed.deinit();
    const r = parsed.value;

    var res = pipeline.query(a, st.root, r.collection, r.query_vector, r.k) catch |e| return errJsonDyn(a, @errorName(e));
    defer res.deinit();

    const outs = a.alloc(QueryOut, res.hits.len) catch return errJson("oom");
    defer a.free(outs);
    for (res.hits, 0..) |h, i| {
        outs[i] = QueryOut{ .score = h.score, .page_start = h.page_start, .page_end = h.page_end, .source = h.source, .text = h.text };
    }
    return jsonOwned(a, outs) catch errJson("oom");
}

/// List collections present under the root. Returns a JSON array of info.
pub export fn librarian_list() callconv(.c) [*:0]const u8 {
    const st = g_state orelse return errJson("not initialised");
    const a = st.allocator;
    const names = store.listIn(a, st.root) catch return errJson("list failed");
    defer {
        for (names) |n| a.free(n);
        a.free(names);
    }
    // Each entry owns its strings: the collection is freed per iteration, so
    // borrowing its slices into the output would be a use-after-free.
    var outs: std.ArrayList(InfoOut) = .{};
    defer {
        for (outs.items) |o| {
            a.free(o.name);
            a.free(o.source);
            a.free(o.backend);
            a.free(o.model);
        }
        outs.deinit(a);
    }
    for (names) |n| {
        var col = store.loadFrom(a, st.root, n) catch continue;
        defer col.deinit();
        const src = if (col.chunks.len > 0) col.chunks[0].source else "";
        const info = InfoOut{
            .name = a.dupe(u8, n) catch return errJson("oom"),
            .source = a.dupe(u8, src) catch return errJson("oom"),
            .backend = a.dupe(u8, col.backend) catch return errJson("oom"),
            .model = a.dupe(u8, col.model) catch return errJson("oom"),
            .dim = col.dim,
            .chunks = col.chunks.len,
            .pages = col.pages,
        };
        outs.append(a, info) catch {
            a.free(info.name);
            a.free(info.source);
            a.free(info.backend);
            a.free(info.model);
            return errJson("oom");
        };
    }
    return jsonOwned(a, outs.items) catch errJson("oom");
}

/// Report a single collection's metadata, or an error if absent.
pub export fn librarian_info(name_ptr: [*]const u8, name_len: usize) callconv(.c) [*:0]const u8 {
    const st = g_state orelse return errJson("not initialised");
    const a = st.allocator;
    const name = name_ptr[0..name_len];
    var col = store.loadFrom(a, st.root, name) catch |e| return errJsonDyn(a, @errorName(e));
    defer col.deinit();
    return jsonOwned(a, infoFromCollection(name, col)) catch errJson("oom");
}

/// Delete a collection. Returns 0 on success, negative on failure.
pub export fn librarian_delete(name_ptr: [*]const u8, name_len: usize) callconv(.c) i32 {
    const st = g_state orelse return -1;
    store.deleteFrom(st.root, name_ptr[0..name_len]) catch return -2;
    return 0;
}

fn infoFromCollection(name: []const u8, col: store.Collection) InfoOut {
    const source: []const u8 = if (col.chunks.len > 0) col.chunks[0].source else "";
    return InfoOut{
        .name = name,
        .source = source,
        .backend = col.backend,
        .model = col.model,
        .dim = col.dim,
        .chunks = col.chunks.len,
        .pages = col.pages,
    };
}

fn errJson(comptime msg: []const u8) [*:0]const u8 {
    return "{\"error\":\"" ++ msg ++ "\"}";
}

/// Runtime error response. Error names are bare identifiers, so no escaping is
/// needed. Falls back to a static literal if the allocation itself fails.
fn errJsonDyn(a: std.mem.Allocator, msg: []const u8) [*:0]const u8 {
    const s = std.fmt.allocPrintSentinel(a, "{{\"error\":\"{s}\"}}", .{msg}, 0) catch return errJson("oom");
    return s.ptr;
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
