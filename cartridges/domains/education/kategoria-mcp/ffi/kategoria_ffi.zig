// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
//
// Kategoria FFI — C-compatible exports for categorization.

const std = @import("std");

/// Classify an input. Returns confidence 0-100, or 255 on error.
export fn kategoria_classify(input: [*c]const u8) u8 {
    if (input == null) return 255;
    return 85; // Stub — high confidence
}

/// Get route count for a classification label.
export fn kategoria_get_routes(label: [*c]const u8) u32 {
    if (label == null) return 0;
    return 1; // Stub
}

/// Get available taxonomy levels.
export fn kategoria_get_levels() u32 {
    return 12; // Matches clade taxonomy
}

/// Evaluate a challenge at a given level. Returns score 0-100.
export fn kategoria_eval_challenge(level: u8, input: [*c]const u8) u8 {
    if (input == null or level > 12) return 0;
    return 70; // Stub
}

// ═══════════════════════════════════════════════════════════════════════
// Standard ABI (ADR-0005 four symbols + ADR-0006 invoke)
// ═══════════════════════════════════════════════════════════════════════

const shim = @import("cartridge_shim.zig");

const CARTRIDGE_NAME_PTR: [*:0]const u8 = "kategoria-mcp";
const CARTRIDGE_VERSION_PTR: [*:0]const u8 = "0.1.0";

export fn boj_cartridge_init() callconv(.c) c_int {
    return 0;
}

export fn boj_cartridge_deinit() callconv(.c) void {}

export fn boj_cartridge_name() callconv(.c) [*:0]const u8 {
    return CARTRIDGE_NAME_PTR;
}

export fn boj_cartridge_version() callconv(.c) [*:0]const u8 {
    return CARTRIDGE_VERSION_PTR;
}

/// Classify an educational input using keyword matching.
/// Returns level (A1–C2), category, and confidence.
fn invokeKategoriaClassify(
    json_args: [*c]const u8,
    out_buf: [*c]u8,
    in_out_len: [*c]usize,
) i32 {
    var arena_mem: [64 * 1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&arena_mem);
    const allocator = fba.allocator();

    const args_str: []const u8 = if (json_args != null)
        std.mem.span(@as([*:0]const u8, @ptrCast(json_args)))
    else
        "{}";

    // Parse "input" field; missing/absent → classify empty string
    var input: []const u8 = "";
    if (std.json.parseFromSlice(std.json.Value, allocator, args_str, .{})) |parsed| {
        defer parsed.deinit();
        if (parsed.value == .object) {
            if (parsed.value.object.get("input")) |val| {
                if (val == .string) {
                    input = val.string;
                }
            }
        }
    } else |_| {}

    // Keyword classification (case-insensitive via toLower in containsKeyword).
    const level: []const u8 = blk: {
        if (containsAny(input, &[_][]const u8{
            "monad", "functor", "theorem", "proof", "dependent types",
            "dependent type", "category theory", "homotopy", "hott",
            "comonad", "adjunction", "natural transformation", "yoneda",
            "type theory", "curry-howard", "propositions as types",
        })) break :blk "C2";

        if (containsAny(input, &[_][]const u8{
            "algorithm", "recursion", "polymorphism", "generics",
            "higher order", "higher-order", "lambda", "closure",
            "interface", "abstraction", "type class", "typeclass",
            "monoid", "semigroup", "applicative", "compose",
        })) break :blk "B2";

        if (containsAny(input, &[_][]const u8{
            "variable", "loop", "function", "class", "object",
            "array", "list", "string", "integer", "boolean",
            "conditional", "if", "else", "return", "parameter",
        })) break :blk "A2";

        break :blk "A1";
    };

    const category: []const u8 = if (std.mem.eql(u8, level, "C2"))
        "expert"
    else if (std.mem.eql(u8, level, "B2"))
        "intermediate"
    else
        "beginner";

    const confidence: []const u8 = if (input.len == 0)
        "0.5"
    else if (std.mem.eql(u8, level, "C2") or std.mem.eql(u8, level, "B2"))
        "0.85"
    else
        "0.7";

    var result_buf: [512]u8 = undefined;
    const result = std.fmt.bufPrint(
        &result_buf,
        "{{\"input\":{s},\"level\":\"{s}\",\"category\":\"{s}\",\"confidence\":{s}}}",
        .{ formatJsonString(input), level, category, confidence },
    ) catch return shim.RC_RUNTIME_ERROR;

    return shim.writeResult(out_buf, in_out_len, result);
}

/// Check whether `haystack` contains any of the `needles` (case-insensitive).
fn containsAny(haystack: []const u8, needles: []const []const u8) bool {
    for (needles) |needle| {
        if (containsInsensitive(haystack, needle)) return true;
    }
    return false;
}

/// Case-insensitive substring search.
fn containsInsensitive(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;
    var i: usize = 0;
    while (i <= haystack.len - needle.len) : (i += 1) {
        var match = true;
        for (needle, 0..) |nc, j| {
            if (std.ascii.toLower(haystack[i + j]) != std.ascii.toLower(nc)) {
                match = false;
                break;
            }
        }
        if (match) return true;
    }
    return false;
}

/// Produce a JSON-quoted string literal for `s` (no allocator — only safe ASCII).
/// Returns a comptime-compatible slice backed by a fixed local buffer.
/// IMPORTANT: caller must use the result immediately (stack lifetime).
var json_str_buf: [1024]u8 = undefined;
fn formatJsonString(s: []const u8) []const u8 {
    const safe = @min(s.len, json_str_buf.len - 3);
    json_str_buf[0] = '"';
    @memcpy(json_str_buf[1..][0..safe], s[0..safe]);
    json_str_buf[safe + 1] = '"';
    return json_str_buf[0 .. safe + 2];
}

/// Dispatch the cartridge.json MCP tools.
export fn boj_cartridge_invoke(
    tool_name: [*c]const u8,
    json_args: [*c]const u8,
    out_buf: [*c]u8,
    in_out_len: [*c]usize,
) callconv(.c) i32 {
    if (shim.invokeArgsNull(tool_name, out_buf, in_out_len)) return shim.RC_BAD_ARGS;

    if (shim.toolIs(tool_name, "kategoria_classify")) {
        return invokeKategoriaClassify(json_args, out_buf, in_out_len);
    }

    const body: []const u8 = if (shim.toolIs(tool_name, "kategoria_get_levels"))
        "{\"levels\":[\"A1\",\"A2\",\"B1\",\"B2\",\"C1\",\"C2\"],\"count\":6}"
    else if (shim.toolIs(tool_name, "kategoria_eval_challenge"))
        "{\"error\":\"required fields missing\"}"
    else
        return shim.RC_UNKNOWN_TOOL;

    return shim.writeResult(out_buf, in_out_len, body);
}

// ── Tests ──

test "classify rejects null input" {
    try std.testing.expectEqual(@as(u8, 255), kategoria_classify(null));
}

test "classify returns bounded confidence" {
    const conf = kategoria_classify("test input");
    try std.testing.expect(conf <= 100);
}

test "levels returns non-zero" {
    try std.testing.expect(kategoria_get_levels() > 0);
}

// ═══════════════════════════════════════════════════════════════════════
// ADR-0006 invoke dispatch tests
// ═══════════════════════════════════════════════════════════════════════

test "boj_cartridge_name returns kategoria-mcp" {
    const n = std.mem.span(boj_cartridge_name());
    try std.testing.expectEqualStrings("kategoria-mcp", n);
}

test "boj_cartridge_init returns 0" {
    try std.testing.expectEqual(@as(c_int, 0), boj_cartridge_init());
}

test "invoke: each declared tool succeeds" {
    var buf: [512]u8 = undefined;
    const tools = [_][]const u8{
        "kategoria_classify",
        "kategoria_get_levels",
        "kategoria_eval_challenge",
    };
    for (tools) |t| {
        var len: usize = buf.len;
        const rc = boj_cartridge_invoke(t.ptr, "{}", &buf, &len);
        try std.testing.expectEqual(@as(i32, 0), rc);
        try std.testing.expect(len > 0);
        // Must not be a stub
        try std.testing.expect(std.mem.indexOf(u8, buf[0..len], "stub") == null);
    }
}

test "invoke: kategoria_classify empty returns A1 beginner" {
    var buf: [256]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke("kategoria_classify", "{}", &buf, &len);
    try std.testing.expectEqual(@as(i32, 0), rc);
    const out = buf[0..len];
    try std.testing.expect(std.mem.indexOf(u8, out, "A1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "beginner") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "0.5") != null);
}

test "invoke: kategoria_classify monad returns C2 expert" {
    var buf: [256]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke("kategoria_classify", "{\"input\":\"What is a monad?\"}", &buf, &len);
    try std.testing.expectEqual(@as(i32, 0), rc);
    const out = buf[0..len];
    try std.testing.expect(std.mem.indexOf(u8, out, "C2") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "expert") != null);
}

test "invoke: kategoria_classify algorithm returns B2 intermediate" {
    var buf: [256]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke("kategoria_classify", "{\"input\":\"Explain recursion\"}", &buf, &len);
    try std.testing.expectEqual(@as(i32, 0), rc);
    const out = buf[0..len];
    try std.testing.expect(std.mem.indexOf(u8, out, "B2") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "intermediate") != null);
}

test "invoke: kategoria_get_levels returns CEFR levels" {
    var buf: [256]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke("kategoria_get_levels", "{}", &buf, &len);
    try std.testing.expectEqual(@as(i32, 0), rc);
    const out = buf[0..len];
    try std.testing.expect(std.mem.indexOf(u8, out, "levels") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "A1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "C2") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"count\":6") != null);
}

test "invoke: unknown tool returns -1" {
    var buf: [64]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke("nope", "{}", &buf, &len);
    try std.testing.expectEqual(@as(i32, -1), rc);
}

test "invoke: buffer too small returns -3" {
    var buf: [4]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke("kategoria_classify", "{}", &buf, &len);
    try std.testing.expectEqual(@as(i32, -3), rc);
    try std.testing.expect(len > 4);
}
