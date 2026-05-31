// SPDX-License-Identifier: MPL-2.0
//
// Extraction: turn a source into one string per page. Plain text and Markdown
// pass through (split on the form-feed boundary if any). PDFs are handed to
// poppler's pdftotext when that binary is present, mirroring the source design;
// page boundaries are the form-feed (\x0c) pdftotext emits. When pdftotext is
// absent or fails, an error is returned so the caller can fall back to text.

const std = @import("std");

pub const Error = error{ PdftotextUnavailable, ExtractionFailed };

const form_feed: u8 = 0x0c;

/// Split text into pages on the form-feed boundary, dropping a single trailing
/// empty page (pdftotext emits a form-feed after the final page). Text with no
/// form-feed yields a single page. The caller owns the slice and each page.
pub fn pagesFromText(allocator: std.mem.Allocator, text: []const u8) ![][]u8 {
    var slices: std.ArrayList([]const u8) = .{};
    defer slices.deinit(allocator);
    var it = std.mem.splitScalar(u8, text, form_feed);
    while (it.next()) |piece| try slices.append(allocator, piece);

    // Drop a single trailing page that is empty or whitespace only.
    if (slices.items.len > 0) {
        const last = slices.items[slices.items.len - 1];
        if (std.mem.trim(u8, last, " \t\r\n").len == 0) {
            _ = slices.pop();
        }
    }

    var pages = try allocator.alloc([]u8, slices.items.len);
    errdefer allocator.free(pages);
    var filled: usize = 0;
    errdefer for (pages[0..filled]) |p| allocator.free(p);
    for (slices.items, 0..) |piece, i| {
        pages[i] = try allocator.dupe(u8, piece);
        filled = i + 1;
    }
    return pages;
}

/// Free pages returned by pagesFromText or extractPdf.
pub fn freePages(allocator: std.mem.Allocator, pages: [][]u8) void {
    for (pages) |p| allocator.free(p);
    allocator.free(pages);
}

/// Extract pages from a PDF by invoking pdftotext. Returns PdftotextUnavailable
/// if the binary cannot be spawned, ExtractionFailed if it exits non-zero.
pub fn extractPdf(allocator: std.mem.Allocator, path: []const u8) ![][]u8 {
    const argv = [_][]const u8{ "pdftotext", path, "-" };
    const res = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &argv,
        .max_output_bytes = 256 * 1024 * 1024,
    }) catch return Error.PdftotextUnavailable;
    defer allocator.free(res.stdout);
    defer allocator.free(res.stderr);

    switch (res.term) {
        .Exited => |code| if (code != 0) return Error.ExtractionFailed,
        else => return Error.ExtractionFailed,
    }
    return pagesFromText(allocator, res.stdout);
}

test "pagesFromText splits on form feed and drops a trailing empty page" {
    const pages = try pagesFromText(std.testing.allocator, "alpha\x0cbeta\x0c");
    defer freePages(std.testing.allocator, pages);
    try std.testing.expectEqual(@as(usize, 2), pages.len);
    try std.testing.expectEqualStrings("alpha", pages[0]);
    try std.testing.expectEqualStrings("beta", pages[1]);
}

test "pagesFromText yields a single page when there is no form feed" {
    const pages = try pagesFromText(std.testing.allocator, "just one page");
    defer freePages(std.testing.allocator, pages);
    try std.testing.expectEqual(@as(usize, 1), pages.len);
    try std.testing.expectEqualStrings("just one page", pages[0]);
}

test "pagesFromText keeps an interior empty page" {
    const pages = try pagesFromText(std.testing.allocator, "a\x0c\x0cb");
    defer freePages(std.testing.allocator, pages);
    try std.testing.expectEqual(@as(usize, 3), pages.len);
    try std.testing.expectEqualStrings("", pages[1]);
}

test "extractPdf on a missing file returns an error" {
    if (extractPdf(std.testing.allocator, "/no/such/file.pdf")) |pages| {
        freePages(std.testing.allocator, pages);
        return error.TestExpectedError;
    } else |err| {
        try std.testing.expect(err == Error.ExtractionFailed or err == Error.PdftotextUnavailable);
    }
}
