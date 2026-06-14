// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// local-memory-mcp FFI — ADR-0006 five-symbol cartridge ABI implementation.
//
// Session-scoped in-memory implementation (no SQLite dependency).
// All state is ephemeral per-invocation; IDs are derived from PID + nanoseconds.

const std = @import("std");
const shim = @import("cartridge_shim.zig");

const CARTRIDGE_NAME_PTR: [*:0]const u8 = "local-memory-mcp";
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

// ── ID helpers ────────────────────────────────────────────────────────

/// Write a unique ID into `buf` with prefix (e.g. "s-", "l-", "d-", "e-").
/// Uses PID + nanosecond timestamp mod 1e9 for uniqueness.
fn makeId(buf: []u8, prefix: []const u8) []const u8 {
    const pid = std.os.linux.getpid();
    const ns = std.time.nanoTimestamp();
    const ns_part: u64 = @intCast(@rem(ns, 1_000_000_000));
    return std.fmt.bufPrint(buf, "{s}{d}-{d}", .{ prefix, pid, ns_part }) catch buf[0..0];
}

/// Current epoch in milliseconds.
fn epochMs() i64 {
    return @intCast(@divTrunc(std.time.nanoTimestamp(), 1_000_000));
}

// ── Args parsing helper ───────────────────────────────────────────────

/// Parse json_args as a JSON object. Returns a parsed value or null.
/// Caller must call parsed.deinit() if non-null.
fn parseArgs(
    allocator: std.mem.Allocator,
    json_args: [*c]const u8,
) ?std.json.Parsed(std.json.Value) {
    const args_str: []const u8 = if (json_args != null)
        std.mem.span(@as([*:0]const u8, @ptrCast(json_args)))
    else
        "{}";

    return std.json.parseFromSlice(std.json.Value, allocator, args_str, .{}) catch null;
}

/// Extract a string field from a parsed JSON object, or return default.
fn getStr(parsed: std.json.Value, field: []const u8, default: []const u8) []const u8 {
    if (parsed == .object) {
        if (parsed.object.get(field)) |val| {
            if (val == .string) return val.string;
        }
    }
    return default;
}

// ── Safe preview: up to 40 chars, skip JSON-breaking characters ───────

fn safePreview(buf: []u8, content: []const u8) []const u8 {
    var j: usize = 0;
    for (content) |c| {
        if (j >= 40) break;
        if (c == '"' or c == '\\' or c == '\n' or c == '\r') break;
        buf[j] = c;
        j += 1;
    }
    return buf[0..j];
}

// ── Tool implementations ──────────────────────────────────────────────

fn memorySessionStart(
    json_args: [*c]const u8,
    out_buf: [*c]u8,
    in_out_len: [*c]usize,
) i32 {
    _ = json_args;

    var id_buf: [64]u8 = undefined;
    const session_id = makeId(&id_buf, "s-");
    const ms = epochMs();

    var result_buf: [512]u8 = undefined;
    const result = std.fmt.bufPrint(
        &result_buf,
        "{{\"session_id\":\"{s}\",\"started_at\":{d},\"context\":[],\"project\":null}}",
        .{ session_id, ms },
    ) catch return shim.RC_RUNTIME_ERROR;

    return shim.writeResult(out_buf, in_out_len, result);
}

fn memorySessionEnd(
    json_args: [*c]const u8,
    out_buf: [*c]u8,
    in_out_len: [*c]usize,
) i32 {
    var arena_mem: [16 * 1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&arena_mem);
    const allocator = fba.allocator();

    var summary: []const u8 = "";
    if (parseArgs(allocator, json_args)) |parsed| {
        defer parsed.deinit();
        summary = getStr(parsed.value, "summary", "");
    }

    // Build safe preview of summary (strip JSON-special chars).
    var prev_buf: [128]u8 = undefined;
    const safe_sum = safePreview(&prev_buf, summary);

    var result_buf: [256]u8 = undefined;
    const result = std.fmt.bufPrint(
        &result_buf,
        "{{\"saved\":true,\"summary\":\"{s}\"}}",
        .{safe_sum},
    ) catch return shim.RC_RUNTIME_ERROR;

    return shim.writeResult(out_buf, in_out_len, result);
}

fn memoryLearn(
    json_args: [*c]const u8,
    out_buf: [*c]u8,
    in_out_len: [*c]usize,
) i32 {
    var arena_mem: [16 * 1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&arena_mem);
    const allocator = fba.allocator();

    var category: []const u8 = "";
    var content: []const u8 = "";
    if (parseArgs(allocator, json_args)) |parsed| {
        defer parsed.deinit();
        category = getStr(parsed.value, "category", "");
        content = getStr(parsed.value, "content", "");
    }

    var id_buf: [64]u8 = undefined;
    const id = makeId(&id_buf, "l-");

    var cat_prev: [64]u8 = undefined;
    const safe_cat = safePreview(&cat_prev, category);

    var prev_buf: [64]u8 = undefined;
    const preview = safePreview(&prev_buf, content);

    var result_buf: [512]u8 = undefined;
    const result = std.fmt.bufPrint(
        &result_buf,
        "{{\"id\":\"{s}\",\"stored\":true,\"category\":\"{s}\",\"preview\":\"{s}\"}}",
        .{ id, safe_cat, preview },
    ) catch return shim.RC_RUNTIME_ERROR;

    return shim.writeResult(out_buf, in_out_len, result);
}

fn memoryRecall(
    json_args: [*c]const u8,
    out_buf: [*c]u8,
    in_out_len: [*c]usize,
) i32 {
    _ = json_args;

    const body = "{\"learnings\":[],\"total\":0,\"note\":\"Session storage only — data does not persist across invocations\"}";
    return shim.writeResult(out_buf, in_out_len, body);
}

fn memorySearch(
    json_args: [*c]const u8,
    out_buf: [*c]u8,
    in_out_len: [*c]usize,
) i32 {
    var arena_mem: [16 * 1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&arena_mem);
    const allocator = fba.allocator();

    var query: []const u8 = "";
    if (parseArgs(allocator, json_args)) |parsed| {
        defer parsed.deinit();
        query = getStr(parsed.value, "query", "");
    }

    var q_buf: [64]u8 = undefined;
    const safe_q = safePreview(&q_buf, query);

    var result_buf: [256]u8 = undefined;
    const result = std.fmt.bufPrint(
        &result_buf,
        "{{\"results\":[],\"total\":0,\"query\":\"{s}\"}}",
        .{safe_q},
    ) catch return shim.RC_RUNTIME_ERROR;

    return shim.writeResult(out_buf, in_out_len, result);
}

fn memoryDecide(
    json_args: [*c]const u8,
    out_buf: [*c]u8,
    in_out_len: [*c]usize,
) i32 {
    var arena_mem: [16 * 1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&arena_mem);
    const allocator = fba.allocator();

    var title: []const u8 = "";
    if (parseArgs(allocator, json_args)) |parsed| {
        defer parsed.deinit();
        title = getStr(parsed.value, "title", "");
    }

    var id_buf: [64]u8 = undefined;
    const id = makeId(&id_buf, "d-");

    var t_buf: [64]u8 = undefined;
    const safe_title = safePreview(&t_buf, title);

    var result_buf: [256]u8 = undefined;
    const result = std.fmt.bufPrint(
        &result_buf,
        "{{\"id\":\"{s}\",\"recorded\":true,\"title\":\"{s}\"}}",
        .{ id, safe_title },
    ) catch return shim.RC_RUNTIME_ERROR;

    return shim.writeResult(out_buf, in_out_len, result);
}

fn memoryEntityObserve(
    json_args: [*c]const u8,
    out_buf: [*c]u8,
    in_out_len: [*c]usize,
) i32 {
    var arena_mem: [16 * 1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&arena_mem);
    const allocator = fba.allocator();

    var entity_name: []const u8 = "";
    if (parseArgs(allocator, json_args)) |parsed| {
        defer parsed.deinit();
        entity_name = getStr(parsed.value, "entityName", "");
    }

    var id_buf: [64]u8 = undefined;
    const id = makeId(&id_buf, "e-");

    var e_buf: [64]u8 = undefined;
    const safe_entity = safePreview(&e_buf, entity_name);

    var result_buf: [256]u8 = undefined;
    const result = std.fmt.bufPrint(
        &result_buf,
        "{{\"id\":\"{s}\",\"recorded\":true,\"entity\":\"{s}\"}}",
        .{ id, safe_entity },
    ) catch return shim.RC_RUNTIME_ERROR;

    return shim.writeResult(out_buf, in_out_len, result);
}

fn memoryEntitySearch(
    json_args: [*c]const u8,
    out_buf: [*c]u8,
    in_out_len: [*c]usize,
) i32 {
    var arena_mem: [16 * 1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&arena_mem);
    const allocator = fba.allocator();

    var query: []const u8 = "";
    if (parseArgs(allocator, json_args)) |parsed| {
        defer parsed.deinit();
        query = getStr(parsed.value, "query", "");
    }

    var q_buf: [64]u8 = undefined;
    const safe_q = safePreview(&q_buf, query);

    var result_buf: [256]u8 = undefined;
    const result = std.fmt.bufPrint(
        &result_buf,
        "{{\"entities\":[],\"total\":0,\"query\":\"{s}\"}}",
        .{safe_q},
    ) catch return shim.RC_RUNTIME_ERROR;

    return shim.writeResult(out_buf, in_out_len, result);
}

fn memoryEntityOpen(
    json_args: [*c]const u8,
    out_buf: [*c]u8,
    in_out_len: [*c]usize,
) i32 {
    _ = json_args;

    const body = "{\"entity\":null,\"note\":\"Provide name or id\"}";
    return shim.writeResult(out_buf, in_out_len, body);
}

fn memoryEntityRelate(
    json_args: [*c]const u8,
    out_buf: [*c]u8,
    in_out_len: [*c]usize,
) i32 {
    var arena_mem: [16 * 1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&arena_mem);
    const allocator = fba.allocator();

    var from_id: []const u8 = "";
    var to_id: []const u8 = "";
    var relation: []const u8 = "";
    if (parseArgs(allocator, json_args)) |parsed| {
        defer parsed.deinit();
        from_id = getStr(parsed.value, "fromEntityId", "");
        to_id = getStr(parsed.value, "toEntityId", "");
        relation = getStr(parsed.value, "relationType", "");
    }

    var f_buf: [64]u8 = undefined;
    var t_buf: [64]u8 = undefined;
    var r_buf: [64]u8 = undefined;
    const safe_from = safePreview(&f_buf, from_id);
    const safe_to = safePreview(&t_buf, to_id);
    const safe_rel = safePreview(&r_buf, relation);

    var result_buf: [512]u8 = undefined;
    const result = std.fmt.bufPrint(
        &result_buf,
        "{{\"recorded\":true,\"from\":\"{s}\",\"to\":\"{s}\",\"relation\":\"{s}\"}}",
        .{ safe_from, safe_to, safe_rel },
    ) catch return shim.RC_RUNTIME_ERROR;

    return shim.writeResult(out_buf, in_out_len, result);
}

fn memoryInsights(
    json_args: [*c]const u8,
    out_buf: [*c]u8,
    in_out_len: [*c]usize,
) i32 {
    _ = json_args;

    const body = "{\"sessions\":0,\"learnings\":0,\"decisions\":0,\"entities\":0,\"note\":\"Session storage only\"}";
    return shim.writeResult(out_buf, in_out_len, body);
}

fn memoryProfileSet(
    json_args: [*c]const u8,
    out_buf: [*c]u8,
    in_out_len: [*c]usize,
) i32 {
    var arena_mem: [16 * 1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&arena_mem);
    const allocator = fba.allocator();

    var field: []const u8 = "";
    if (parseArgs(allocator, json_args)) |parsed| {
        defer parsed.deinit();
        field = getStr(parsed.value, "field", "");
    }

    var f_buf: [64]u8 = undefined;
    const safe_field = safePreview(&f_buf, field);

    var result_buf: [256]u8 = undefined;
    const result = std.fmt.bufPrint(
        &result_buf,
        "{{\"stored\":true,\"field\":\"{s}\"}}",
        .{safe_field},
    ) catch return shim.RC_RUNTIME_ERROR;

    return shim.writeResult(out_buf, in_out_len, result);
}

fn memoryProfileGet(
    json_args: [*c]const u8,
    out_buf: [*c]u8,
    in_out_len: [*c]usize,
) i32 {
    var arena_mem: [16 * 1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&arena_mem);
    const allocator = fba.allocator();

    var field: []const u8 = "";
    if (parseArgs(allocator, json_args)) |parsed| {
        defer parsed.deinit();
        field = getStr(parsed.value, "field", "");
    }

    var f_buf: [64]u8 = undefined;
    const safe_field = safePreview(&f_buf, field);

    var result_buf: [256]u8 = undefined;
    const result = std.fmt.bufPrint(
        &result_buf,
        "{{\"found\":false,\"field\":\"{s}\",\"value\":null}}",
        .{safe_field},
    ) catch return shim.RC_RUNTIME_ERROR;

    return shim.writeResult(out_buf, in_out_len, result);
}

// ── ADR-0006 dispatch ─────────────────────────────────────────────────

export fn boj_cartridge_invoke(
    tool_name: [*c]const u8,
    json_args: [*c]const u8,
    out_buf: [*c]u8,
    in_out_len: [*c]usize,
) callconv(.c) i32 {
    if (shim.invokeArgsNull(tool_name, out_buf, in_out_len)) return shim.RC_BAD_ARGS;

    if (shim.toolIs(tool_name, "memory_session_start"))
        return memorySessionStart(json_args, out_buf, in_out_len);
    if (shim.toolIs(tool_name, "memory_session_end"))
        return memorySessionEnd(json_args, out_buf, in_out_len);
    if (shim.toolIs(tool_name, "memory_learn"))
        return memoryLearn(json_args, out_buf, in_out_len);
    if (shim.toolIs(tool_name, "memory_recall"))
        return memoryRecall(json_args, out_buf, in_out_len);
    if (shim.toolIs(tool_name, "memory_search"))
        return memorySearch(json_args, out_buf, in_out_len);
    if (shim.toolIs(tool_name, "memory_decide"))
        return memoryDecide(json_args, out_buf, in_out_len);
    if (shim.toolIs(tool_name, "memory_entity_observe"))
        return memoryEntityObserve(json_args, out_buf, in_out_len);
    if (shim.toolIs(tool_name, "memory_entity_search"))
        return memoryEntitySearch(json_args, out_buf, in_out_len);
    if (shim.toolIs(tool_name, "memory_entity_open"))
        return memoryEntityOpen(json_args, out_buf, in_out_len);
    if (shim.toolIs(tool_name, "memory_entity_relate"))
        return memoryEntityRelate(json_args, out_buf, in_out_len);
    if (shim.toolIs(tool_name, "memory_insights"))
        return memoryInsights(json_args, out_buf, in_out_len);
    if (shim.toolIs(tool_name, "memory_profile_set"))
        return memoryProfileSet(json_args, out_buf, in_out_len);
    if (shim.toolIs(tool_name, "memory_profile_get"))
        return memoryProfileGet(json_args, out_buf, in_out_len);

    return shim.RC_UNKNOWN_TOOL;
}

// ── Tests ─────────────────────────────────────────────────────────────

test "boj_cartridge_name returns local-memory-mcp" {
    try std.testing.expectEqualStrings("local-memory-mcp", std.mem.span(boj_cartridge_name()));
}

test "boj_cartridge_init returns 0" {
    try std.testing.expectEqual(@as(c_int, 0), boj_cartridge_init());
}

test "invoke unknown tool returns RC_UNKNOWN_TOOL" {
    var buf: [256]u8 = undefined;
    var len: usize = buf.len;
    try std.testing.expectEqual(@as(i32, shim.RC_UNKNOWN_TOOL), boj_cartridge_invoke("unknown_xyz", "{}", &buf, &len));
}

test "invoke memory_session_start returns 0 and has session_id" {
    var buf: [512]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke("memory_session_start", "{}", &buf, &len);
    try std.testing.expectEqual(@as(i32, 0), rc);
    const out = buf[0..len];
    try std.testing.expect(std.mem.indexOf(u8, out, "session_id") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "started_at") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "stub") == null);
}

test "invoke memory_learn returns stored:true" {
    var buf: [512]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke("memory_learn", "{\"category\":\"pattern\",\"content\":\"hello world\"}", &buf, &len);
    try std.testing.expectEqual(@as(i32, 0), rc);
    const out = buf[0..len];
    try std.testing.expect(std.mem.indexOf(u8, out, "\"stored\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "stub") == null);
}

test "invoke memory_recall returns empty list" {
    var buf: [512]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke("memory_recall", "{}", &buf, &len);
    try std.testing.expectEqual(@as(i32, 0), rc);
    const out = buf[0..len];
    try std.testing.expect(std.mem.indexOf(u8, out, "learnings") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "stub") == null);
}

test "invoke memory_insights returns session storage note" {
    var buf: [512]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke("memory_insights", "{}", &buf, &len);
    try std.testing.expectEqual(@as(i32, 0), rc);
    const out = buf[0..len];
    try std.testing.expect(std.mem.indexOf(u8, out, "sessions") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "stub") == null);
}
