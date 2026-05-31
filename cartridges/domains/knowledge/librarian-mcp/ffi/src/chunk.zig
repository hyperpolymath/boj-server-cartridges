// SPDX-License-Identifier: MPL-2.0
//
// Chunking: greedy word-window chunks with overlap, tracking the page span
// each chunk covers. Page index is the document position (1-based), not any
// printed page number; queries cite the document page. Each page is cleaned
// before tokenising. Mirrors the chunking stage of the source RAG design.

const std = @import("std");
const clean = @import("clean.zig");

pub const Chunk = struct {
    id: usize,
    text: []u8,
    page_start: usize,
    page_end: usize,
};

pub const ChunkSet = struct {
    chunks: []Chunk,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ChunkSet) void {
        for (self.chunks) |c| self.allocator.free(c.text);
        self.allocator.free(self.chunks);
    }
};

const Token = struct {
    word: []const u8,
    page: usize,
};

/// Chunk a sequence of page strings into overlapping word windows.
pub fn chunkPages(
    allocator: std.mem.Allocator,
    pages: []const []const u8,
    target_words: usize,
    overlap_words: usize,
) !ChunkSet {
    // Scratch arena for the cleaned pages and the flattened token list; freed
    // wholesale once the chunk texts have been copied into the caller's slices.
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();

    var tokens: std.ArrayList(Token) = .{};
    for (pages, 1..) |raw, page| {
        const cleaned = try clean.clean(scratch, raw);
        var it = std.mem.tokenizeAny(u8, cleaned, " \t\n");
        while (it.next()) |w| {
            try tokens.append(scratch, Token{ .word = w, .page = page });
        }
    }

    var chunks: std.ArrayList(Chunk) = .{};
    errdefer {
        for (chunks.items) |c| allocator.free(c.text);
        chunks.deinit(allocator);
    }

    const step = if (target_words > overlap_words) target_words - overlap_words else 1;
    var id: usize = 0;
    var start: usize = 0;
    while (start < tokens.items.len) : (start += step) {
        const end = @min(start + target_words, tokens.items.len);
        const window = tokens.items[start..end];
        if (window.len == 0) break;

        var text: std.ArrayList(u8) = .{};
        errdefer text.deinit(allocator);
        var page_start = window[0].page;
        var page_end = window[0].page;
        for (window, 0..) |tok, k| {
            if (k > 0) try text.append(allocator, ' ');
            try text.appendSlice(allocator, tok.word);
            page_start = @min(page_start, tok.page);
            page_end = @max(page_end, tok.page);
        }

        try chunks.append(allocator, Chunk{
            .id = id,
            .text = try text.toOwnedSlice(allocator),
            .page_start = page_start,
            .page_end = page_end,
        });
        id += 1;
        if (start + target_words >= tokens.items.len) break;
    }

    return ChunkSet{ .chunks = try chunks.toOwnedSlice(allocator), .allocator = allocator };
}

test "yields one window when target exceeds the token count" {
    const pages = [_][]const u8{"alpha beta"};
    var set = try chunkPages(std.testing.allocator, &pages, 10, 0);
    defer set.deinit();
    try std.testing.expectEqual(@as(usize, 1), set.chunks.len);
    try std.testing.expectEqualStrings("alpha beta", set.chunks[0].text);
    try std.testing.expectEqual(@as(usize, 1), set.chunks[0].page_start);
    try std.testing.expectEqual(@as(usize, 1), set.chunks[0].page_end);
    try std.testing.expectEqual(@as(usize, 0), set.chunks[0].id);
}

test "splits into windows by step with no overlap" {
    const pages = [_][]const u8{ "alpha beta", "gamma" };
    var set = try chunkPages(std.testing.allocator, &pages, 2, 0);
    defer set.deinit();
    try std.testing.expectEqual(@as(usize, 2), set.chunks.len);
    try std.testing.expectEqualStrings("alpha beta", set.chunks[0].text);
    try std.testing.expectEqual(@as(usize, 1), set.chunks[0].page_end);
    try std.testing.expectEqualStrings("gamma", set.chunks[1].text);
    try std.testing.expectEqual(@as(usize, 2), set.chunks[1].page_start);
    try std.testing.expectEqual(@as(usize, 2), set.chunks[1].page_end);
    try std.testing.expectEqual(@as(usize, 1), set.chunks[1].id);
}

test "overlap repeats words and a window can span pages" {
    const pages = [_][]const u8{ "alpha beta", "gamma" };
    var set = try chunkPages(std.testing.allocator, &pages, 2, 1);
    defer set.deinit();
    try std.testing.expectEqual(@as(usize, 2), set.chunks.len);
    try std.testing.expectEqualStrings("alpha beta", set.chunks[0].text);
    try std.testing.expectEqualStrings("beta gamma", set.chunks[1].text);
    try std.testing.expectEqual(@as(usize, 1), set.chunks[1].page_start);
    try std.testing.expectEqual(@as(usize, 2), set.chunks[1].page_end);
}

test "applies cleaning before tokenising" {
    const pages = [_][]const u8{"Col-\norado rocks"};
    var set = try chunkPages(std.testing.allocator, &pages, 10, 0);
    defer set.deinit();
    try std.testing.expectEqual(@as(usize, 1), set.chunks.len);
    try std.testing.expectEqualStrings("Colorado rocks", set.chunks[0].text);
}

test "yields no chunks for empty input" {
    const pages = [_][]const u8{""};
    var set = try chunkPages(std.testing.allocator, &pages, 10, 0);
    defer set.deinit();
    try std.testing.expectEqual(@as(usize, 0), set.chunks.len);
}
