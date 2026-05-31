// SPDX-License-Identifier: MPL-2.0
//
// Embedding helpers. The "hash" backend is a deterministic bag-of-hashed-words
// embedding computed entirely in-process: offline, dependency-free, and used
// by tests and dry runs. Real semantic vectors arrive from the host via
// the "hf" backend (HuggingFace feature-extraction through ml-mcp); for those
// the core only normalises. Unlike the source design's use of a salted hash,
// this hash is stable across runs so persisted indices remain valid.

const std = @import("std");

/// Dimensionality of the hash backend's vectors.
pub const hash_dim: usize = 512;

fn isWord(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

/// Normalise a vector to unit L2 length in place. A vector whose norm is
/// negligible is left untouched, so an all-zero vector stays all-zero rather
/// than becoming NaN.
pub fn normalize(vec: []f32) void {
    var sum: f64 = 0;
    for (vec) |x| sum += @as(f64, x) * @as(f64, x);
    const norm = @sqrt(sum);
    if (norm < 1e-8) return;
    for (vec) |*x| x.* = @floatCast(@as(f64, x.*) / norm);
}

/// Embed text with the deterministic hash backend. The caller owns the slice.
pub fn hashEmbed(allocator: std.mem.Allocator, text: []const u8) ![]f32 {
    const out = try allocator.alloc(f32, hash_dim);
    @memset(out, 0);
    // Accumulate a bag of hashed, lower-cased words into fixed buckets.
    var i: usize = 0;
    while (i < text.len) {
        if (!isWord(text[i])) {
            i += 1;
            continue;
        }
        const start = i;
        while (i < text.len and isWord(text[i])) i += 1;
        var buf: [256]u8 = undefined;
        const word = text[start..i];
        const lowered = if (word.len <= buf.len)
            std.ascii.lowerString(buf[0..word.len], word)
        else
            word;
        const bucket = std.hash.Wyhash.hash(0, lowered) % hash_dim;
        out[bucket] += 1.0;
    }
    normalize(out);
    return out;
}

test "hash embedding of text with words is unit length" {
    const v = try hashEmbed(std.testing.allocator, "the quick brown fox");
    defer std.testing.allocator.free(v);
    var sum: f64 = 0;
    for (v) |x| sum += @as(f64, x) * @as(f64, x);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), @sqrt(sum), 1e-5);
}

test "hash embedding is deterministic" {
    const a = try hashEmbed(std.testing.allocator, "knowledge dimension");
    defer std.testing.allocator.free(a);
    const b = try hashEmbed(std.testing.allocator, "knowledge dimension");
    defer std.testing.allocator.free(b);
    try std.testing.expectEqualSlices(f32, a, b);
}

test "different texts yield different hash embeddings" {
    const a = try hashEmbed(std.testing.allocator, "cat");
    defer std.testing.allocator.free(a);
    const b = try hashEmbed(std.testing.allocator, "dog");
    defer std.testing.allocator.free(b);
    try std.testing.expect(!std.mem.eql(f32, a, b));
}

test "hash embedding is case-insensitive and ignores punctuation" {
    const a = try hashEmbed(std.testing.allocator, "Cat!");
    defer std.testing.allocator.free(a);
    const b = try hashEmbed(std.testing.allocator, "cat");
    defer std.testing.allocator.free(b);
    try std.testing.expectEqualSlices(f32, a, b);
}

test "normalise turns a known vector into unit length" {
    var v = [_]f32{ 3.0, 4.0 };
    normalize(&v);
    try std.testing.expectApproxEqAbs(@as(f32, 0.6), v[0], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), v[1], 1e-6);
}

test "normalise leaves an all-zero vector untouched" {
    var v = [_]f32{ 0.0, 0.0, 0.0 };
    normalize(&v);
    for (v) |x| try std.testing.expectEqual(@as(f32, 0.0), x);
}
