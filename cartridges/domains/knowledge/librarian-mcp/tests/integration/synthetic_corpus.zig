// SPDX-License-Identifier: MPL-2.0
//
// Integration: build an index over a small synthetic corpus with the offline
// hash backend, then query it and assert the expected passage ranks first.
// Exercises extract -> clean -> chunk -> embed -> store -> load -> search end
// to end without any network or external model.

const std = @import("std");
const librarian = @import("librarian");
const pipeline = librarian.pipeline;
const embed = librarian.embed;

// External view of the C ABI, as the host sees it.
extern fn librarian_init(root_ptr: [*]const u8, root_len: usize) c_int;
extern fn librarian_shutdown() c_int;
extern fn librarian_free_string(s: [*:0]const u8) void;
extern fn librarian_hash_embed(text_ptr: [*]const u8, text_len: usize) [*:0]const u8;
extern fn librarian_chunk(req_ptr: [*]const u8, req_len: usize) [*:0]const u8;
extern fn librarian_commit(req_ptr: [*]const u8, req_len: usize) [*:0]const u8;
extern fn librarian_query(req_ptr: [*]const u8, req_len: usize) [*:0]const u8;
extern fn librarian_list() [*:0]const u8;
extern fn librarian_delete(name_ptr: [*]const u8, name_len: usize) c_int;

test "build then query a synthetic corpus with the hash backend" {
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Two pages, one form-feed apart, with clearly separable vocabulary.
    const doc =
        "the analyze category uses verbs such as differentiate organize attribute compare" ++
        "\x0c" ++
        "the knowledge dimension has factual conceptual procedural metacognitive subtypes";

    // One chunk per page: page one is eleven words, so an eleven-word window
    // with no overlap keeps the two pages in separate chunks.
    var extracted = try pipeline.extractAndChunk(a, .{ .text = doc, .chunk_words = 11, .overlap = 0 });
    defer extracted.deinit();
    try std.testing.expectEqual(@as(usize, 2), extracted.pages);
    try std.testing.expect(extracted.set.chunks.len >= 2);

    const vectors = try pipeline.hashEmbedChunks(a, extracted.set);
    defer a.free(vectors);

    const committed = try pipeline.commit(a, tmp.dir, .{
        .name = "taxonomy",
        .source = "taxonomy.txt",
        .backend = "hash",
        .model = "",
        .chunk_words = 11,
        .overlap = 0,
        .pages = extracted.pages,
        .dim = embed.hash_dim,
        .set = extracted.set,
        .vectors = vectors,
    });
    try std.testing.expectEqual(extracted.set.chunks.len, committed);

    // Query: phrasing aligned with page 1 should surface a page-1 passage.
    const qv = try embed.hashEmbed(a, "verbs for the analyze category");
    defer a.free(qv);
    var res = try pipeline.query(a, tmp.dir, "taxonomy", qv, 3);
    defer res.deinit();

    try std.testing.expect(res.hits.len >= 1);
    try std.testing.expectEqual(@as(usize, 1), res.hits[0].page_start);
    try std.testing.expect(std.mem.indexOf(u8, res.hits[0].text, "analyze") != null);
    try std.testing.expectEqualStrings("taxonomy.txt", res.hits[0].source);
}

fn stringify(a: std.mem.Allocator, value: anytype) ![]u8 {
    var w = std.Io.Writer.Allocating.init(a);
    defer w.deinit();
    try std.json.Stringify.value(value, .{}, &w.writer);
    return a.dupe(u8, w.written());
}

test "full round trip through the C ABI with the hash backend" {
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(a, ".");
    defer a.free(root);

    try std.testing.expectEqual(@as(c_int, 0), librarian_init(root.ptr, root.len));
    defer _ = librarian_shutdown();

    const doc =
        "the analyze category uses verbs such as differentiate organize attribute compare" ++
        "\x0c" ++
        "the knowledge dimension has factual conceptual procedural metacognitive subtypes";

    // 1. Chunk the document through the ABI.
    const ChunkOut = struct { id: usize, text: []const u8, page_start: usize, page_end: usize };
    const ChunkReq = struct { text: []const u8, chunk_words: usize, overlap: usize };
    const chunk_req = try stringify(a, ChunkReq{ .text = doc, .chunk_words = 11, .overlap = 0 });
    defer a.free(chunk_req);
    const chunk_resp = librarian_chunk(chunk_req.ptr, chunk_req.len);
    defer librarian_free_string(chunk_resp);
    const ChunkResp = struct { pages: usize, chunks: []ChunkOut };
    const chunks_parsed = try std.json.parseFromSlice(ChunkResp, a, std.mem.span(chunk_resp), .{});
    defer chunks_parsed.deinit();
    try std.testing.expectEqual(@as(usize, 2), chunks_parsed.value.pages);
    try std.testing.expectEqual(@as(usize, 2), chunks_parsed.value.chunks.len);

    // 2. Embed each chunk through the ABI's hash backend.
    const Embedded = struct { dim: usize, vector: []f32 };
    var vectors: std.ArrayList([]f32) = .{};
    defer {
        for (vectors.items) |v| a.free(v);
        vectors.deinit(a);
    }
    var dim: usize = 0;
    for (chunks_parsed.value.chunks) |c| {
        const er = librarian_hash_embed(c.text.ptr, c.text.len);
        defer librarian_free_string(er);
        const ep = try std.json.parseFromSlice(Embedded, a, std.mem.span(er), .{});
        defer ep.deinit();
        dim = ep.value.dim;
        try vectors.append(a, try a.dupe(f32, ep.value.vector));
    }

    // 3. Commit the collection through the ABI.
    const CommitReq = struct {
        collection: []const u8,
        source: []const u8,
        backend: []const u8,
        dim: usize,
        chunks: []ChunkOut,
        vectors: [][]f32,
    };
    const commit_req = try stringify(a, CommitReq{
        .collection = "taxonomy",
        .source = "taxonomy.txt",
        .backend = "hash",
        .dim = dim,
        .chunks = chunks_parsed.value.chunks,
        .vectors = vectors.items,
    });
    defer a.free(commit_req);
    const commit_resp = librarian_commit(commit_req.ptr, commit_req.len);
    defer librarian_free_string(commit_resp);
    try std.testing.expect(std.mem.indexOf(u8, std.mem.span(commit_resp), "\"chunks_added\":2") != null);

    // 4. Query through the ABI.
    const qv = try embed.hashEmbed(a, "verbs for the analyze category");
    defer a.free(qv);
    const QueryReq = struct { collection: []const u8, query_vector: []f32, k: usize };
    const query_req = try stringify(a, QueryReq{ .collection = "taxonomy", .query_vector = qv, .k = 3 });
    defer a.free(query_req);
    const query_resp = librarian_query(query_req.ptr, query_req.len);
    defer librarian_free_string(query_resp);
    const QueryOut = struct { score: f32, page_start: usize, page_end: usize, source: []const u8, text: []const u8 };
    const hits_parsed = try std.json.parseFromSlice([]QueryOut, a, std.mem.span(query_resp), .{});
    defer hits_parsed.deinit();
    try std.testing.expect(hits_parsed.value.len >= 1);
    try std.testing.expectEqual(@as(usize, 1), hits_parsed.value[0].page_start);
    try std.testing.expect(std.mem.indexOf(u8, hits_parsed.value[0].text, "analyze") != null);

    // 5. List through the ABI (entries must own their strings, not borrow from
    // a freed collection).
    const list_resp = librarian_list();
    defer librarian_free_string(list_resp);
    try std.testing.expect(std.mem.indexOf(u8, std.mem.span(list_resp), "taxonomy") != null);
    try std.testing.expect(std.mem.indexOf(u8, std.mem.span(list_resp), "\"backend\":\"hash\"") != null);

    // 6. Delete through the ABI.
    try std.testing.expectEqual(@as(c_int, 0), librarian_delete("taxonomy", "taxonomy".len));
}
