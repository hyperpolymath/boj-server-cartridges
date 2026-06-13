// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
//
// textkit-mcp FFI — pure-computation text utilities.
//
// Implements ADR-0006 five-symbol ABI.  All tools are pure functions:
// no network, no filesystem, no credential access (grant = "").
//
// Tools:
//   encode_base64 — RFC 4648 base64-encode a UTF-8 text string.

const std = @import("std");
const shim = @import("cartridge_shim.zig");

const NAME: [*:0]const u8 = "textkit-mcp";
const VERSION: [*:0]const u8 = "0.1.0";

export fn boj_cartridge_init() callconv(.c) c_int {
    return 0;
}

export fn boj_cartridge_deinit() callconv(.c) void {}

export fn boj_cartridge_name() callconv(.c) [*:0]const u8 {
    return NAME;
}

export fn boj_cartridge_version() callconv(.c) [*:0]const u8 {
    return VERSION;
}

// ─── encode_base64 ───────────────────────────────────────────────────

fn encodeBase64(
    json_args: [*c]const u8,
    out_buf: [*c]u8,
    in_out_len: [*c]usize,
) i32 {
    // Use a fixed stack arena — no heap allocation required.
    var arena_mem: [256 * 1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&arena_mem);
    const allocator = fba.allocator();

    // Parse "text" field from JSON args. If parsing fails or field is
    // absent, treat text as the empty string (encode_base64("") = "").
    var text: []const u8 = "";
    const args_str: []const u8 = if (json_args != null)
        std.mem.span(@as([*:0]const u8, @ptrCast(json_args)))
    else
        "{}";

    if (std.json.parseFromSlice(std.json.Value, allocator, args_str, .{})) |parsed| {
        defer parsed.deinit();
        if (parsed.value == .object) {
            if (parsed.value.object.get("text")) |val| {
                if (val == .string) {
                    text = val.string;
                }
            }
        }
    } else |_| {
        // Silently ignore parse errors — default to empty string.
    }

    // Base64-encode the text.
    const encoded_len = std.base64.standard.Encoder.calcSize(text.len);
    const encoded_buf = allocator.alloc(u8, encoded_len) catch return shim.RC_RUNTIME_ERROR;
    const encoded = std.base64.standard.Encoder.encode(encoded_buf, text);

    // Build result JSON: {"base64":"<encoded>"}
    // base64 alphabet is [A-Za-z0-9+/=] — no JSON escaping needed.
    var result_buf: [4 * 1024]u8 = undefined;
    const result = std.fmt.bufPrint(
        &result_buf,
        "{{\"base64\":\"{s}\"}}",
        .{encoded},
    ) catch return shim.RC_RUNTIME_ERROR;

    return shim.writeResult(out_buf, in_out_len, result);
}

// ─── ADR-0006 dispatch ───────────────────────────────────────────────

export fn boj_cartridge_invoke(
    tool_name: [*c]const u8,
    json_args: [*c]const u8,
    out_buf: [*c]u8,
    in_out_len: [*c]usize,
) callconv(.c) i32 {
    if (shim.invokeArgsNull(tool_name, out_buf, in_out_len)) return shim.RC_BAD_ARGS;

    if (shim.toolIs(tool_name, "encode_base64")) {
        return encodeBase64(json_args, out_buf, in_out_len);
    }
    return shim.RC_UNKNOWN_TOOL;
}

// ─── Tests ───────────────────────────────────────────────────────────

test "encode_base64: hello world" {
    var buf: [256]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke(
        "encode_base64",
        "{\"text\":\"Hello, World!\"}",
        &buf,
        &len,
    );
    try std.testing.expectEqual(@as(i32, 0), rc);
    const out = buf[0..len];
    // Hello, World! → SGVsbG8sIFdvcmxkIQ==
    try std.testing.expect(std.mem.indexOf(u8, out, "SGVsbG8sIFdvcmxkIQ==") != null);
}

test "encode_base64: empty text" {
    var buf: [256]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke("encode_base64", "{\"text\":\"\"}", &buf, &len);
    try std.testing.expectEqual(@as(i32, 0), rc);
    const out = buf[0..len];
    try std.testing.expect(std.mem.indexOf(u8, out, "\"base64\":\"\"") != null);
}

test "encode_base64: empty args returns base64 of empty string" {
    var buf: [256]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke("encode_base64", "{}", &buf, &len);
    try std.testing.expectEqual(@as(i32, 0), rc);
    const out = buf[0..len];
    // result must NOT be a stub
    try std.testing.expect(std.mem.indexOf(u8, out, "\"status\":\"stub\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"base64\"") != null);
}

test "encode_base64: result is not a stub" {
    var buf: [256]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke("encode_base64", "{\"text\":\"BoJ\"}", &buf, &len);
    try std.testing.expectEqual(@as(i32, 0), rc);
    const out = buf[0..len];
    try std.testing.expect(std.mem.indexOf(u8, out, "stub") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"base64\"") != null);
}

test "unknown tool returns -1" {
    var buf: [64]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke("no_such_tool", "{}", &buf, &len);
    try std.testing.expectEqual(@as(i32, -1), rc);
}

test "null tool_name returns -2" {
    var buf: [64]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke(null, "{}", &buf, &len);
    try std.testing.expectEqual(@as(i32, -2), rc);
}

test "buffer too small returns -3" {
    var buf: [4]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke("encode_base64", "{\"text\":\"hello\"}", &buf, &len);
    try std.testing.expectEqual(@as(i32, -3), rc);
    try std.testing.expect(len > 4);
}

test "init and deinit are no-ops" {
    try std.testing.expectEqual(@as(c_int, 0), boj_cartridge_init());
    boj_cartridge_deinit();
}

test "name and version" {
    try std.testing.expectEqualStrings("textkit-mcp", std.mem.span(boj_cartridge_name()));
    try std.testing.expectEqualStrings("0.1.0", std.mem.span(boj_cartridge_version()));
}
