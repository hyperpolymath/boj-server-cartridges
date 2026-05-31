// SPDX-License-Identifier: MPL-2.0
//
// On-disk collection persistence. Each named collection is a directory holding
// three files: vectors.bin (a small header then row-major unit-norm f32 rows),
// chunks.json (the chunk metadata), and meta.json (the index parameters). The
// vector blob is host-endian, fit for a local, ownable index. Collection names
// must pass slug validation, closing path traversal as a write-safety property.

const std = @import("std");

pub const Error = error{ InvalidName, CollectionNotFound, BadFormat };

pub const StoredChunk = struct {
    id: usize,
    text: []const u8,
    page_start: usize,
    page_end: usize,
    source: []const u8,
};

pub const Collection = struct {
    allocator: std.mem.Allocator,
    dim: usize,
    chunk_words: usize,
    overlap: usize,
    pages: usize,
    backend: []const u8,
    model: []const u8,
    vectors: []f32,
    chunks: []StoredChunk,

    /// Free everything a loaded collection owns. Do not call on a collection
    /// assembled from borrowed literals (as in the tests' inputs to saveTo).
    pub fn deinit(self: *Collection) void {
        const a = self.allocator;
        for (self.chunks) |c| {
            a.free(c.text);
            a.free(c.source);
        }
        a.free(self.chunks);
        a.free(self.vectors);
        a.free(self.backend);
        a.free(self.model);
    }
};

const magic = "LBV1";
const max_file_bytes = 256 * 1024 * 1024;

const MetaJson = struct {
    dim: usize,
    chunk_words: usize,
    overlap: usize,
    pages: usize,
    backend: []const u8,
    model: []const u8,
};

/// A collection name is path-safe when it is non-empty, at most 64 bytes, and
/// composed solely of ASCII alphanumerics, hyphen, and underscore. This admits
/// no path separator, no dot, and so no traversal.
pub fn validateSlug(name: []const u8) bool {
    if (name.len == 0 or name.len > 64) return false;
    for (name) |c| {
        if (!(std.ascii.isAlphanumeric(c) or c == '-' or c == '_')) return false;
    }
    return true;
}

pub fn saveTo(allocator: std.mem.Allocator, root_dir: std.fs.Dir, name: []const u8, col: Collection) !void {
    if (!validateSlug(name)) return Error.InvalidName;

    // Stage into a sibling temporary directory, then swap it into place, so a
    // reader never sees a half-written collection.
    const tmp_name = try std.fmt.allocPrint(allocator, "{s}.staging", .{name});
    defer allocator.free(tmp_name);
    root_dir.deleteTree(tmp_name) catch {};
    try root_dir.makePath(tmp_name);
    {
        var dir = try root_dir.openDir(tmp_name, .{});
        defer dir.close();

        // vectors.bin: magic, dim, count, then the raw f32 rows (host-endian).
        const count: u64 = if (col.dim == 0) 0 else col.vectors.len / col.dim;
        const dim64: u64 = col.dim;
        var blob: std.ArrayList(u8) = .{};
        defer blob.deinit(allocator);
        try blob.appendSlice(allocator, magic);
        try blob.appendSlice(allocator, std.mem.asBytes(&dim64));
        try blob.appendSlice(allocator, std.mem.asBytes(&count));
        try blob.appendSlice(allocator, std.mem.sliceAsBytes(col.vectors));
        try dir.writeFile(.{ .sub_path = "vectors.bin", .data = blob.items });

        // chunks.json
        var cw = std.Io.Writer.Allocating.init(allocator);
        defer cw.deinit();
        try std.json.Stringify.value(col.chunks, .{}, &cw.writer);
        try dir.writeFile(.{ .sub_path = "chunks.json", .data = cw.written() });

        // meta.json
        const meta = MetaJson{
            .dim = col.dim,
            .chunk_words = col.chunk_words,
            .overlap = col.overlap,
            .pages = col.pages,
            .backend = col.backend,
            .model = col.model,
        };
        var mw = std.Io.Writer.Allocating.init(allocator);
        defer mw.deinit();
        try std.json.Stringify.value(meta, .{}, &mw.writer);
        try dir.writeFile(.{ .sub_path = "meta.json", .data = mw.written() });
    }
    root_dir.deleteTree(name) catch {};
    try root_dir.rename(tmp_name, name);
}

pub fn loadFrom(allocator: std.mem.Allocator, root_dir: std.fs.Dir, name: []const u8) !Collection {
    if (!validateSlug(name)) return Error.InvalidName;
    var dir = root_dir.openDir(name, .{}) catch return Error.CollectionNotFound;
    defer dir.close();

    const meta_bytes = dir.readFileAlloc(allocator, "meta.json", max_file_bytes) catch return Error.CollectionNotFound;
    defer allocator.free(meta_bytes);
    const meta_parsed = try std.json.parseFromSlice(MetaJson, allocator, meta_bytes, .{});
    defer meta_parsed.deinit();

    const vec_bytes = dir.readFileAlloc(allocator, "vectors.bin", max_file_bytes) catch return Error.CollectionNotFound;
    defer allocator.free(vec_bytes);
    if (vec_bytes.len < magic.len + 16) return Error.BadFormat;
    if (!std.mem.eql(u8, vec_bytes[0..magic.len], magic)) return Error.BadFormat;
    const dim = std.mem.bytesToValue(u64, vec_bytes[4..12]);
    const count = std.mem.bytesToValue(u64, vec_bytes[12..20]);
    const payload = vec_bytes[20..];
    if (payload.len != count * dim * @sizeOf(f32)) return Error.BadFormat;
    const vectors = try allocator.alloc(f32, count * dim);
    errdefer allocator.free(vectors);
    @memcpy(std.mem.sliceAsBytes(vectors), payload);

    const chunk_bytes = dir.readFileAlloc(allocator, "chunks.json", max_file_bytes) catch return Error.CollectionNotFound;
    defer allocator.free(chunk_bytes);
    const chunk_parsed = try std.json.parseFromSlice([]StoredChunk, allocator, chunk_bytes, .{});
    defer chunk_parsed.deinit();

    var chunks = try allocator.alloc(StoredChunk, chunk_parsed.value.len);
    errdefer allocator.free(chunks);
    for (chunk_parsed.value, 0..) |c, i| {
        chunks[i] = StoredChunk{
            .id = c.id,
            .text = try allocator.dupe(u8, c.text),
            .page_start = c.page_start,
            .page_end = c.page_end,
            .source = try allocator.dupe(u8, c.source),
        };
    }

    return Collection{
        .allocator = allocator,
        .dim = @intCast(dim),
        .chunk_words = meta_parsed.value.chunk_words,
        .overlap = meta_parsed.value.overlap,
        .pages = meta_parsed.value.pages,
        .backend = try allocator.dupe(u8, meta_parsed.value.backend),
        .model = try allocator.dupe(u8, meta_parsed.value.model),
        .vectors = vectors,
        .chunks = chunks,
    };
}

pub fn existsIn(root_dir: std.fs.Dir, name: []const u8) bool {
    if (!validateSlug(name)) return false;
    var dir = root_dir.openDir(name, .{}) catch return false;
    defer dir.close();
    dir.access("meta.json", .{}) catch return false;
    return true;
}

pub fn deleteFrom(root_dir: std.fs.Dir, name: []const u8) !void {
    if (!validateSlug(name)) return Error.InvalidName;
    if (!existsIn(root_dir, name)) return Error.CollectionNotFound;
    try root_dir.deleteTree(name);
}

/// List the names of collections present under the root. Caller owns the slice
/// and each name within it.
pub fn listIn(allocator: std.mem.Allocator, root_dir: std.fs.Dir) ![][]u8 {
    var iter_dir = try root_dir.openDir(".", .{ .iterate = true });
    defer iter_dir.close();

    var names: std.ArrayList([]u8) = .{};
    errdefer {
        for (names.items) |n| allocator.free(n);
        names.deinit(allocator);
    }
    var it = iter_dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .directory) continue;
        if (!existsIn(root_dir, entry.name)) continue;
        try names.append(allocator, try allocator.dupe(u8, entry.name));
    }
    return names.toOwnedSlice(allocator);
}

// ── Tests ──

fn sampleCollection() Collection {
    return Collection{
        .allocator = undefined,
        .dim = 2,
        .chunk_words = 220,
        .overlap = 45,
        .pages = 3,
        .backend = "hash",
        .model = "BAAI/bge-small-en-v1.5",
        .vectors = @constCast(&[_]f32{ 1.0, 0.0, 0.0, 1.0 }),
        .chunks = @constCast(&[_]StoredChunk{
            .{ .id = 0, .text = "alpha \"quoted\"\nline", .page_start = 1, .page_end = 1, .source = "book.pdf" },
            .{ .id = 1, .text = "beta", .page_start = 2, .page_end = 3, .source = "book.pdf" },
        }),
    };
}

test "validateSlug accepts safe names" {
    try std.testing.expect(validateSlug("alpha"));
    try std.testing.expect(validateSlug("my-book_2"));
    try std.testing.expect(validateSlug("Book2"));
}

test "validateSlug rejects traversal and unsafe names" {
    try std.testing.expect(!validateSlug(""));
    try std.testing.expect(!validateSlug(".."));
    try std.testing.expect(!validateSlug("a/b"));
    try std.testing.expect(!validateSlug("a.b"));
    try std.testing.expect(!validateSlug("a b"));
    try std.testing.expect(!validateSlug("x" ** 65));
}

test "save then load round-trips the collection" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try saveTo(std.testing.allocator, tmp.dir, "book", sampleCollection());

    var loaded = try loadFrom(std.testing.allocator, tmp.dir, "book");
    defer loaded.deinit();

    try std.testing.expectEqual(@as(usize, 2), loaded.dim);
    try std.testing.expectEqual(@as(usize, 220), loaded.chunk_words);
    try std.testing.expectEqual(@as(usize, 45), loaded.overlap);
    try std.testing.expectEqual(@as(usize, 3), loaded.pages);
    try std.testing.expectEqualStrings("hash", loaded.backend);
    try std.testing.expectEqualSlices(f32, &[_]f32{ 1.0, 0.0, 0.0, 1.0 }, loaded.vectors);
    try std.testing.expectEqual(@as(usize, 2), loaded.chunks.len);
    try std.testing.expectEqualStrings("alpha \"quoted\"\nline", loaded.chunks[0].text);
    try std.testing.expectEqual(@as(usize, 3), loaded.chunks[1].page_end);
    try std.testing.expectEqualStrings("book.pdf", loaded.chunks[1].source);
}

test "saveTo rejects an invalid collection name" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try std.testing.expectError(Error.InvalidName, saveTo(std.testing.allocator, tmp.dir, "../escape", sampleCollection()));
}

test "loadFrom an unknown collection reports CollectionNotFound" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try std.testing.expectError(Error.CollectionNotFound, loadFrom(std.testing.allocator, tmp.dir, "ghost"));
}

test "existsIn and deleteFrom reflect presence" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try std.testing.expect(!existsIn(tmp.dir, "book"));
    try saveTo(std.testing.allocator, tmp.dir, "book", sampleCollection());
    try std.testing.expect(existsIn(tmp.dir, "book"));
    try deleteFrom(tmp.dir, "book");
    try std.testing.expect(!existsIn(tmp.dir, "book"));
}

test "listIn returns saved collection names" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try saveTo(std.testing.allocator, tmp.dir, "book", sampleCollection());
    try saveTo(std.testing.allocator, tmp.dir, "notes", sampleCollection());

    const names = try listIn(std.testing.allocator, tmp.dir);
    defer {
        for (names) |n| std.testing.allocator.free(n);
        std.testing.allocator.free(names);
    }
    try std.testing.expectEqual(@as(usize, 2), names.len);
    var seen_book = false;
    var seen_notes = false;
    for (names) |n| {
        if (std.mem.eql(u8, n, "book")) seen_book = true;
        if (std.mem.eql(u8, n, "notes")) seen_notes = true;
    }
    try std.testing.expect(seen_book and seen_notes);
}
