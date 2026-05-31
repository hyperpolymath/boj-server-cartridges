// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
//
// npc-mcp FFI -- ADR-0006 five-symbol cartridge ABI.
//
// Transport model (Option A: the mod dials out). The Fabric mod opens an
// outbound connection to the host and drives the cartridge through ordinary
// tool calls: it POSTs each Minecraft event to `npc_ingest_event` and polls
// `npc_drain_commands` for queued actions. The cartridge therefore holds no
// socket of its own; it is a passive request/response state machine layered
// over the deterministic Zig perception core in src/npcmcp.zig.

const std = @import("std");
const shim = @import("cartridge_shim.zig");
const core = @import("src/npcmcp.zig");

const CARTRIDGE_NAME_PTR: [*:0]const u8 = "npc-mcp";
const CARTRIDGE_VERSION_PTR: [*:0]const u8 = "0.1.0";

export fn boj_cartridge_init() callconv(.c) c_int {
    return core.npc_init();
}

export fn boj_cartridge_deinit() callconv(.c) void {
    _ = core.npc_shutdown();
}

export fn boj_cartridge_name() callconv(.c) [*:0]const u8 {
    return CARTRIDGE_NAME_PTR;
}

export fn boj_cartridge_version() callconv(.c) [*:0]const u8 {
    return CARTRIDGE_VERSION_PTR;
}

export fn boj_cartridge_invoke(
    tool_name: [*c]const u8,
    json_args: [*c]const u8,
    out_buf: [*c]u8,
    in_out_len: [*c]usize,
) callconv(.c) i32 {
    if (shim.invokeArgsNull(tool_name, out_buf, in_out_len)) return shim.RC_BAD_ARGS;
    const args: []const u8 = if (json_args == null)
        "{}"
    else
        std.mem.span(@as([*:0]const u8, @ptrCast(json_args)));

    // Perception queries (read-only, never persona-gated).
    if (shim.toolIs(tool_name, "npc_get_narrative_context") or
        shim.toolIs(tool_name, "npc_get_world_state"))
    {
        return coreStringResult(core.npc_narrative_context(), out_buf, in_out_len);
    }
    if (shim.toolIs(tool_name, "npc_get_recent_events")) {
        return coreStringResult(core.npc_get_raw_events(parseCount(args)), out_buf, in_out_len);
    }

    // Event intake: the mod POSTs one protocol event; the whole args object is
    // that event envelope.
    if (shim.toolIs(tool_name, "npc_ingest_event")) {
        const rc = core.npc_ingest_event(args.ptr, args.len);
        const body = if (rc == 0)
            "{\"result\":{\"ok\":true}}"
        else
            "{\"result\":{\"ok\":false,\"error\":\"ingest_failed\"}}";
        return shim.writeResult(out_buf, in_out_len, body);
    }

    // Command drain: the mod polls for queued commands to execute.
    if (shim.toolIs(tool_name, "npc_drain_commands")) {
        return coreStringResult(core.npc_drain_commands(), out_buf, in_out_len);
    }

    // Persona load: args is the persona object itself (no outer wrapper).
    if (shim.toolIs(tool_name, "npc_load_persona")) {
        const rc = core.npc_load_persona_json(args.ptr, args.len);
        const body = if (rc == 0)
            "{\"result\":{\"ok\":true}}"
        else
            "{\"result\":{\"ok\":false,\"error\":\"persona_load_failed\"}}";
        return shim.writeResult(out_buf, in_out_len, body);
    }

    // Command tools: persona-gated, enqueued as protocol v1 command envelopes
    // for the mod to drain and execute.
    const cmd_type: ?[]const u8 = if (shim.toolIs(tool_name, "npc_say"))
        "say"
    else if (shim.toolIs(tool_name, "npc_give"))
        "give"
    else if (shim.toolIs(tool_name, "npc_execute_command"))
        "execute_command"
    else
        null;
    if (cmd_type) |ctype| {
        const tn = std.mem.span(@as([*:0]const u8, @ptrCast(tool_name)));
        const allowed = core.npc_is_tool_allowed(tn.ptr, tn.len);
        if (allowed == 0)
            return shim.writeResult(out_buf, in_out_len, "{\"result\":{\"ok\":false,\"error\":\"denied_by_persona\"}}");
        if (allowed < 0)
            return shim.writeResult(out_buf, in_out_len, "{\"result\":{\"ok\":false,\"error\":\"no_persona_loaded\"}}");
        return enqueueCommand(ctype, args, out_buf, in_out_len);
    }

    return shim.RC_UNKNOWN_TOOL;
}

// ## Helpers

/// Copy a core-allocated NUL-terminated string into the caller buffer and
/// release it. Mirrors the core's own ownership contract: every string the
/// core returns through this path is freed with `npc_free_string`.
fn coreStringResult(core_ptr: [*:0]const u8, out_buf: [*c]u8, in_out_len: [*c]usize) i32 {
    const s = std.mem.span(core_ptr);
    const rc = shim.writeResult(out_buf, in_out_len, s);
    core.npc_free_string(core_ptr);
    return rc;
}

/// Wrap `payload` (the tool's raw JSON args) in a protocol v1 command envelope
/// and enqueue it for the mod to drain.
fn enqueueCommand(cmd_type: []const u8, payload: []const u8, out_buf: [*c]u8, in_out_len: [*c]usize) i32 {
    const ts = std.time.milliTimestamp();
    var id_buf: [40]u8 = undefined;
    const id = std.fmt.bufPrint(&id_buf, "cmd-{d}", .{ts}) catch return shim.RC_RUNTIME_ERROR;

    const envelope = std.fmt.allocPrint(
        std.heap.page_allocator,
        "{{\"v\":1,\"type\":\"{s}\",\"ts\":{d},\"id\":\"{s}\",\"payload\":{s}}}",
        .{ cmd_type, ts, id, payload },
    ) catch return shim.RC_RUNTIME_ERROR;
    defer std.heap.page_allocator.free(envelope);

    if (core.npc_enqueue_command(envelope.ptr, envelope.len) != 0)
        return shim.writeResult(out_buf, in_out_len, "{\"result\":{\"ok\":false,\"error\":\"enqueue_failed\"}}");

    var body_buf: [80]u8 = undefined;
    const body = std.fmt.bufPrint(&body_buf, "{{\"result\":{{\"ok\":true,\"id\":\"{s}\"}}}}", .{id}) catch return shim.RC_RUNTIME_ERROR;
    return shim.writeResult(out_buf, in_out_len, body);
}

/// Parse `{"count": N}` from the args; default to 20 recent events.
fn parseCount(args: []const u8) usize {
    const Shape = struct { count: ?usize = null };
    const parsed = std.json.parseFromSlice(Shape, std.heap.page_allocator, args, .{
        .ignore_unknown_fields = true,
    }) catch return 20;
    defer parsed.deinit();
    return parsed.value.count orelse 20;
}

// ## Tests

test "name and version" {
    try std.testing.expectEqualStrings("npc-mcp", std.mem.span(boj_cartridge_name()));
    try std.testing.expectEqualStrings("0.1.0", std.mem.span(boj_cartridge_version()));
}

test "unknown tool returns RC_UNKNOWN_TOOL" {
    var buf: [64]u8 = undefined;
    var len: usize = buf.len;
    try std.testing.expectEqual(@as(i32, shim.RC_UNKNOWN_TOOL), boj_cartridge_invoke("nope", "{}", &buf, &len));
}

// One lifecycle per process: the core's npc_shutdown destroys its global
// allocator, so init/deinit cannot be cycled. The host inits once and deinits
// once; this single test mirrors that and exercises the full invoke surface.
test "cartridge lifecycle: ingest, query, persona gate" {
    try std.testing.expectEqual(@as(c_int, 0), boj_cartridge_init());
    defer boj_cartridge_deinit();

    var buf: [8192]u8 = undefined;
    var len: usize = buf.len;

    // A command tool fails closed before any persona is loaded.
    len = buf.len;
    try std.testing.expectEqual(@as(i32, 0), boj_cartridge_invoke("npc_say", "{\"message\":\"hi\"}", &buf, &len));
    try std.testing.expect(std.mem.indexOf(u8, buf[0..len], "no_persona_loaded") != null);

    // Ingesting a player_join then querying narrative context surfaces the player.
    const ev =
        \\{"v":1,"type":"player_join","ts":1,"id":"e1","payload":{"player":{"name":"Alex","uuid":"u-alex"},"position":[0.0,64.0,0.0],"dimension":"minecraft:overworld","gamemode":"survival","first_join":true}}
    ;
    len = buf.len;
    try std.testing.expectEqual(@as(i32, 0), boj_cartridge_invoke("npc_ingest_event", ev, &buf, &len));

    len = buf.len;
    try std.testing.expectEqual(@as(i32, 0), boj_cartridge_invoke("npc_get_narrative_context", "{}", &buf, &len));
    try std.testing.expect(std.mem.indexOf(u8, buf[0..len], "Alex") != null);
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
