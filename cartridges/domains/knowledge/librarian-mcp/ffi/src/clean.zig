// SPDX-License-Identifier: MPL-2.0
//
// Text cleaning: de-hyphenate words broken across a line, reflow soft-wrapped
// lines within a paragraph, collapse whitespace, and preserve blank-line
// paragraph breaks. Mirrors the cleaning stage of the source RAG design.

const std = @import("std");

fn isWord(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

fn isSpaceOrTab(c: u8) bool {
    return c == ' ' or c == '\t';
}

/// De-hyphenate words broken across a line: a word character, a hyphen, any
/// horizontal whitespace, a newline, more horizontal whitespace, then a word
/// character become the two word characters joined. The caller owns the slice.
fn dehyphenate(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .{};
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (i < text.len) {
        const c = text[i];
        if (c == '-' and out.items.len > 0 and isWord(out.items[out.items.len - 1])) {
            var j = i + 1;
            while (j < text.len and isSpaceOrTab(text[j])) j += 1;
            if (j < text.len and text[j] == '\n') {
                j += 1;
                while (j < text.len and isSpaceOrTab(text[j])) j += 1;
                if (j < text.len and isWord(text[j])) {
                    // Drop the hyphen, the newline, and the surrounding spaces.
                    i = j;
                    continue;
                }
            }
        }
        try out.append(allocator, c);
        i += 1;
    }
    return out.toOwnedSlice(allocator);
}

/// Reflow a single paragraph: soft-wrap newlines (with their surrounding
/// horizontal whitespace) collapse to one space, runs of horizontal whitespace
/// collapse to one space, and the result is trimmed.
fn reflowParagraph(allocator: std.mem.Allocator, para: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .{};
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (i < para.len) {
        const c = para[i];
        if (isSpaceOrTab(c) or c == '\n') {
            // Consume a maximal run of whitespace including at most the
            // newlines that turn soft wraps into a single space.
            while (i < para.len and (isSpaceOrTab(para[i]) or para[i] == '\n')) i += 1;
            try out.append(allocator, ' ');
            continue;
        }
        try out.append(allocator, c);
        i += 1;
    }
    const trimmed = std.mem.trim(u8, out.items, " ");
    const owned = try allocator.dupe(u8, trimmed);
    out.deinit(allocator);
    return owned;
}

/// Clean raw extracted text. The caller owns the returned slice.
pub fn clean(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    const dehyphenated = try dehyphenate(allocator, text);
    defer allocator.free(dehyphenated);

    var out: std.ArrayList(u8) = .{};
    errdefer out.deinit(allocator);

    // Split on blank-line paragraph breaks: a newline, optional horizontal
    // whitespace, then another newline. Each paragraph is reflowed; empty
    // paragraphs are dropped.
    var start: usize = 0;
    var i: usize = 0;
    var wrote_any = false;
    while (i < dehyphenated.len) {
        if (dehyphenated[i] == '\n') {
            var j = i + 1;
            while (j < dehyphenated.len and isSpaceOrTab(dehyphenated[j])) j += 1;
            if (j < dehyphenated.len and dehyphenated[j] == '\n') {
                try emitParagraph(allocator, &out, dehyphenated[start..i], &wrote_any);
                i = j + 1;
                start = i;
                continue;
            }
        }
        i += 1;
    }
    try emitParagraph(allocator, &out, dehyphenated[start..], &wrote_any);

    return out.toOwnedSlice(allocator);
}

fn emitParagraph(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    para: []const u8,
    wrote_any: *bool,
) !void {
    const reflowed = try reflowParagraph(allocator, para);
    defer allocator.free(reflowed);
    if (reflowed.len == 0) return;
    if (wrote_any.*) try out.appendSlice(allocator, "\n\n");
    try out.appendSlice(allocator, reflowed);
    wrote_any.* = true;
}

test "de-hyphenates a word split across a line" {
    const out = try clean(std.testing.allocator, "Col-\norado");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("Colorado", out);
}

test "reflows a soft-wrapped line within a paragraph" {
    const out = try clean(std.testing.allocator, "hello\nworld");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("hello world", out);
}

test "preserves a blank-line paragraph break" {
    const out = try clean(std.testing.allocator, "first\n\nsecond");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("first\n\nsecond", out);
}

test "collapses runs of spaces and tabs" {
    const out = try clean(std.testing.allocator, "a   \t b");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("a b", out);
}

test "drops empty paragraphs and trims" {
    const out = try clean(std.testing.allocator, "  alpha  \n\n\n\n  beta  ");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("alpha\n\nbeta", out);
}
