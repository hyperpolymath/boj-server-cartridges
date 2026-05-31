// SPDX-License-Identifier: MPL-2.0
//
// Brute-force cosine search over unit-norm vectors. For a single book (a few
// thousand vectors) this is instant, so there is no vector-index dependency.
// Vectors are stored row-major and flattened; every row and the query are
// assumed unit length, so cosine similarity is a dot product.

const std = @import("std");

pub const Hit = struct {
    index: usize,
    score: f32,
};

pub const Error = error{DimMismatch};

/// Return the top-k rows by cosine similarity to the query, highest first,
/// ties broken by ascending row index. The caller owns the returned slice.
pub fn topK(
    allocator: std.mem.Allocator,
    vectors: []const f32,
    dim: usize,
    query: []const f32,
    k: usize,
) ![]Hit {
    if (query.len != dim) return Error.DimMismatch;
    const count = if (dim == 0) 0 else vectors.len / dim;

    var hits = try allocator.alloc(Hit, count);
    errdefer allocator.free(hits);
    for (0..count) |row| {
        const base = row * dim;
        var dot: f32 = 0;
        for (0..dim) |d| dot += vectors[base + d] * query[d];
        hits[row] = Hit{ .index = row, .score = dot };
    }

    std.sort.block(Hit, hits, {}, lessByScore);

    const n = @min(k, count);
    const result = try allocator.alloc(Hit, n);
    @memcpy(result, hits[0..n]);
    allocator.free(hits);
    return result;
}

fn lessByScore(_: void, a: Hit, b: Hit) bool {
    if (a.score != b.score) return a.score > b.score;
    return a.index < b.index;
}

test "ranks rows by cosine similarity, highest first" {
    const vectors = [_]f32{ 1, 0, 0, 1, 0.70710677, 0.70710677 };
    const query = [_]f32{ 1, 0 };
    const hits = try topK(std.testing.allocator, &vectors, 2, &query, 3);
    defer std.testing.allocator.free(hits);
    try std.testing.expectEqual(@as(usize, 3), hits.len);
    try std.testing.expectEqual(@as(usize, 0), hits[0].index);
    try std.testing.expectEqual(@as(usize, 2), hits[1].index);
    try std.testing.expectEqual(@as(usize, 1), hits[2].index);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), hits[0].score, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), hits[2].score, 1e-6);
}

test "returns at most k hits" {
    const vectors = [_]f32{ 1, 0, 0, 1, 0.70710677, 0.70710677 };
    const query = [_]f32{ 1, 0 };
    const hits = try topK(std.testing.allocator, &vectors, 2, &query, 2);
    defer std.testing.allocator.free(hits);
    try std.testing.expectEqual(@as(usize, 2), hits.len);
}

test "k larger than the row count returns every row" {
    const vectors = [_]f32{ 1, 0, 0, 1 };
    const query = [_]f32{ 1, 0 };
    const hits = try topK(std.testing.allocator, &vectors, 2, &query, 99);
    defer std.testing.allocator.free(hits);
    try std.testing.expectEqual(@as(usize, 2), hits.len);
}

test "breaks score ties by ascending index" {
    const vectors = [_]f32{ 1, 0, 1, 0 };
    const query = [_]f32{ 1, 0 };
    const hits = try topK(std.testing.allocator, &vectors, 2, &query, 2);
    defer std.testing.allocator.free(hits);
    try std.testing.expectEqual(@as(usize, 0), hits[0].index);
    try std.testing.expectEqual(@as(usize, 1), hits[1].index);
}

test "empty index returns no hits" {
    const vectors = [_]f32{};
    const query = [_]f32{ 1, 0 };
    const hits = try topK(std.testing.allocator, &vectors, 2, &query, 5);
    defer std.testing.allocator.free(hits);
    try std.testing.expectEqual(@as(usize, 0), hits.len);
}

test "rejects a query whose dimension differs from the rows" {
    const vectors = [_]f32{ 1, 0, 0, 1 };
    const query = [_]f32{ 1, 0, 0 };
    try std.testing.expectError(Error.DimMismatch, topK(std.testing.allocator, &vectors, 2, &query, 5));
}
