// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// SSG-MCP Cartridge — Zig FFI bridge for static site generation operations.
//
// Models the build pipeline state machine from SafeSsg.idr. These process-local
// transitions do not read content, invoke a generator, start a preview server,
// deploy a site or clean files. Native tool dispatch is explicitly unavailable.

const std = @import("std");

// ═══════════════════════════════════════════════════════════════════════
// Types (must match SsgMcp.SafeSsg encodings)
// ═══════════════════════════════════════════════════════════════════════

pub const SsgState = enum(c_int) {
    empty = 0,
    content_loaded = 1,
    built = 2,
    previewing = 3,
    ready_to_deploy = 4,
    deployed = 5,
    ssg_error = 6,
};

pub const SsgEngine = enum(c_int) {
    hugo = 1,
    zola = 2,
    astro = 3,
    casket = 4,
    custom = 99,
};

// ═══════════════════════════════════════════════════════════════════════
// Build Pipeline State Machine
// ═══════════════════════════════════════════════════════════════════════

const MAX_SITES: usize = 8;

const SiteSlot = struct {
    active: bool,
    engine: SsgEngine,
    state: SsgState,
    content_hash: u32, // Hash of content for cache invalidation
};

var sites: [MAX_SITES]SiteSlot = [_]SiteSlot{.{
    .active = false,
    .engine = .hugo,
    .state = .empty,
    .content_hash = 0,
}} ** MAX_SITES;

var mutex: shim.Mutex = .{};

/// Validate a state transition (matches Idris2 canTransition).
fn isValidTransition(from: SsgState, to: SsgState) bool {
    return switch (from) {
        .empty => to == .content_loaded,
        .content_loaded => to == .built or to == .ssg_error,
        .built => to == .previewing or to == .built, // rebuild allowed
        .previewing => to == .ready_to_deploy,
        .ready_to_deploy => to == .deployed or to == .empty or to == .ssg_error,
        .deployed => to == .empty,
        .ssg_error => to == .empty,
    };
}

// Internal model operations: these are deliberately not C-ABI exports. Their
// transitions preserve the design experiment, not an implementation of an SSG.
/// Model content loading into a free slot using a valid SsgEngine code and content hash.
/// Returns the slot index, or -1 if all slots are active.
fn ssg_load_content(engine: c_int, content_hash: u32) c_int {
    mutex.lock();
    defer mutex.unlock();
    for (&sites, 0..) |*slot, i| {
        if (!slot.active) {
            slot.active = true;
            slot.engine = @enumFromInt(engine);
            slot.state = .content_loaded;
            slot.content_hash = content_hash;
            return @intCast(i);
        }
    }
    return -1; // No slots available
}

/// Mark a loaded or already built model slot as built; no site is generated.
/// Returns 0 on success, -1 for an invalid or inactive slot, or -2 for an
/// invalid state transition.
fn ssg_build(slot_idx: c_int) c_int {
    mutex.lock();
    defer mutex.unlock();
    if (slot_idx < 0 or slot_idx >= MAX_SITES) return -1;
    const idx: usize = @intCast(slot_idx);
    if (!sites[idx].active) return -1;
    if (!isValidTransition(sites[idx].state, .built)) return -2;

    sites[idx].state = .built;
    return 0;
}

/// Mark a built model slot as previewing; no preview server is started.
/// Returns 0 on success, -1 for an invalid or inactive slot, or -2 if the
/// slot is not built.
fn ssg_preview(slot_idx: c_int) c_int {
    mutex.lock();
    defer mutex.unlock();
    if (slot_idx < 0 or slot_idx >= MAX_SITES) return -1;
    const idx: usize = @intCast(slot_idx);
    if (!sites[idx].active) return -1;
    // SAFETY: Must be in Built state — cannot preview unbuilt content
    if (sites[idx].state != .built) return -2;
    if (!isValidTransition(sites[idx].state, .previewing)) return -2;

    sites[idx].state = .previewing;
    return 0;
}

/// Mark preview as complete, transition to ReadyToDeploy.
/// Returns 0 on success, -1 for an invalid or inactive slot, or -2 if the
/// slot is not previewing.
fn ssg_ready_deploy(slot_idx: c_int) c_int {
    mutex.lock();
    defer mutex.unlock();
    if (slot_idx < 0 or slot_idx >= MAX_SITES) return -1;
    const idx: usize = @intCast(slot_idx);
    if (!sites[idx].active) return -1;
    if (!isValidTransition(sites[idx].state, .ready_to_deploy)) return -2;

    sites[idx].state = .ready_to_deploy;
    return 0;
}

/// Mark a model slot as deployed without deploying a site. The slot must be
/// ReadyToDeploy, so the model cannot skip previewing.
/// Returns 0 on success, -1 for an invalid or inactive slot, or -2 if the
/// slot is not ready to deploy.
fn ssg_deploy(slot_idx: c_int) c_int {
    mutex.lock();
    defer mutex.unlock();
    if (slot_idx < 0 or slot_idx >= MAX_SITES) return -1;
    const idx: usize = @intCast(slot_idx);
    if (!sites[idx].active) return -1;
    // SAFETY: Must be in ReadyToDeploy state — cannot skip preview
    if (sites[idx].state != .ready_to_deploy) return -2;
    if (!isValidTransition(sites[idx].state, .deployed)) return -2;

    sites[idx].state = .deployed;
    return 0;
}

/// Release a model slot in ReadyToDeploy, Deployed or SsgError state; no
/// files are removed. Returns 0 on success, -1 for an invalid or inactive
/// slot, or -2 for an invalid state transition.
fn ssg_clean(slot_idx: c_int) c_int {
    mutex.lock();
    defer mutex.unlock();
    if (slot_idx < 0 or slot_idx >= MAX_SITES) return -1;
    const idx: usize = @intCast(slot_idx);
    if (!sites[idx].active) return -1;
    if (!isValidTransition(sites[idx].state, .empty)) return -2;

    sites[idx].active = false;
    sites[idx].state = .empty;
    sites[idx].content_hash = 0;
    return 0;
}

/// Get a slot's model state, or Empty for an inactive slot. Returns -1 for
/// an out-of-range slot index.
fn ssg_state(slot_idx: c_int) c_int {
    mutex.lock();
    defer mutex.unlock();
    if (slot_idx < 0 or slot_idx >= MAX_SITES) return -1;
    const idx: usize = @intCast(slot_idx);
    if (!sites[idx].active) return @intFromEnum(SsgState.empty);
    return @intFromEnum(sites[idx].state);
}

/// Return 1 if the transition between two valid SsgState codes is allowed, else 0.
fn ssg_can_transition(from: c_int, to: c_int) c_int {
    mutex.lock();
    defer mutex.unlock();
    const f: SsgState = @enumFromInt(from);
    const t: SsgState = @enumFromInt(to);
    return if (isValidTransition(f, t)) 1 else 0;
}

/// Reset all model slots to Empty and clear their content hashes.
fn ssg_reset() void {
    mutex.lock();
    defer mutex.unlock();
    for (&sites) |*slot| {
        slot.active = false;
        slot.state = .empty;
        slot.content_hash = 0;
    }
}

// ═══════════════════════════════════════════════════════════════════════
// Standard Cartridge Interface (these four symbols plus invoke below)
// ═══════════════════════════════════════════════════════════════════════

/// Initialise the ssg-mcp cartridge. Resets all site slots.
pub export fn boj_cartridge_init() c_int {
    ssg_reset();
    return 0;
}

/// Deinitialise the ssg-mcp cartridge. Resets all site slots.
pub export fn boj_cartridge_deinit() void {
    ssg_reset();
}

/// Return the cartridge name as a null-terminated C string.
pub export fn boj_cartridge_name() [*:0]const u8 {
    mutex.lock();
    defer mutex.unlock();
    return "ssg-mcp";
}

/// Return the cartridge version as a null-terminated C string.
pub export fn boj_cartridge_version() [*:0]const u8 {
    mutex.lock();
    defer mutex.unlock();
    return "0.1.0";
}

// ═══════════════════════════════════════════════════════════════════════
// ADR-0006 dispatch (boj_cartridge_invoke, 5th standard symbol)
// ═══════════════════════════════════════════════════════════════════════

pub const shim = @import("cartridge_shim.zig");

/// Report the cartridge.json MCP tools as unavailable; json_args is ignored.
/// For a recognised tool, write an unavailable JSON result and return
/// RC_RUNTIME_ERROR. `in_out_len` supplies the output capacity in bytes and
/// receives the written or required length. An undersized buffer returns
/// RC_BUFFER_TOO_SMALL; null required pointers return RC_BAD_ARGS and an
/// unknown tool returns RC_UNKNOWN_TOOL.
pub export fn boj_cartridge_invoke(
    tool_name: [*c]const u8,
    json_args: [*c]const u8,
    out_buf: [*c]u8,
    in_out_len: [*c]usize,
) callconv(.c) i32 {
    _ = json_args;
    if (shim.invokeArgsNull(tool_name, out_buf, in_out_len)) return shim.RC_BAD_ARGS;

    if (!shim.toolIs(tool_name, "ssg_load_content") and
        !shim.toolIs(tool_name, "ssg_build") and
        !shim.toolIs(tool_name, "ssg_preview") and
        !shim.toolIs(tool_name, "ssg_deploy") and
        !shim.toolIs(tool_name, "ssg_clean")) return shim.RC_UNKNOWN_TOOL;

    const rc = shim.writeResult(out_buf, in_out_len, "{\"success\":false,\"status\":\"unavailable\",\"error\":\"ssg-mcp native backend is not implemented\"}");
    return if (rc == shim.RC_SUCCESS) shim.RC_RUNTIME_ERROR else rc;
}

// ═══════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════

test "load content and clean" {
    ssg_reset();
    const slot = ssg_load_content(@intFromEnum(SsgEngine.hugo), 0xABCD);
    try std.testing.expect(slot >= 0);
    try std.testing.expectEqual(@as(c_int, @intFromEnum(SsgState.content_loaded)), ssg_state(slot));
    // Cannot clean from content_loaded (must build first)
    try std.testing.expectEqual(@as(c_int, -2), ssg_clean(slot));
}

test "cannot deploy without preview" {
    ssg_reset();
    const slot = ssg_load_content(@intFromEnum(SsgEngine.zola), 0x1234);
    _ = ssg_build(slot);
    // Attempt to deploy directly from built — MUST fail
    try std.testing.expectEqual(@as(c_int, -2), ssg_deploy(slot));
    // State should remain built
    try std.testing.expectEqual(@as(c_int, @intFromEnum(SsgState.built)), ssg_state(slot));
}

test "cannot preview without build" {
    ssg_reset();
    const slot = ssg_load_content(@intFromEnum(SsgEngine.astro), 0x5678);
    // Attempt to preview from content_loaded — MUST fail
    try std.testing.expectEqual(@as(c_int, -2), ssg_preview(slot));
}

test "full pipeline: load -> build -> preview -> ready -> deploy" {
    ssg_reset();
    const slot = ssg_load_content(@intFromEnum(SsgEngine.casket), 0xCAFE);
    try std.testing.expectEqual(@as(c_int, 0), ssg_build(slot));
    try std.testing.expectEqual(@as(c_int, @intFromEnum(SsgState.built)), ssg_state(slot));
    try std.testing.expectEqual(@as(c_int, 0), ssg_preview(slot));
    try std.testing.expectEqual(@as(c_int, @intFromEnum(SsgState.previewing)), ssg_state(slot));
    try std.testing.expectEqual(@as(c_int, 0), ssg_ready_deploy(slot));
    try std.testing.expectEqual(@as(c_int, @intFromEnum(SsgState.ready_to_deploy)), ssg_state(slot));
    try std.testing.expectEqual(@as(c_int, 0), ssg_deploy(slot));
    try std.testing.expectEqual(@as(c_int, @intFromEnum(SsgState.deployed)), ssg_state(slot));
}

test "rebuild allowed" {
    ssg_reset();
    const slot = ssg_load_content(@intFromEnum(SsgEngine.hugo), 0xAAAA);
    try std.testing.expectEqual(@as(c_int, 0), ssg_build(slot));
    try std.testing.expectEqual(@as(c_int, 0), ssg_build(slot)); // rebuild
    try std.testing.expectEqual(@as(c_int, @intFromEnum(SsgState.built)), ssg_state(slot));
}

test "clean after deploy" {
    ssg_reset();
    const slot = ssg_load_content(@intFromEnum(SsgEngine.zola), 0xBBBB);
    _ = ssg_build(slot);
    _ = ssg_preview(slot);
    _ = ssg_ready_deploy(slot);
    _ = ssg_deploy(slot);
    try std.testing.expectEqual(@as(c_int, 0), ssg_clean(slot));
    try std.testing.expectEqual(@as(c_int, @intFromEnum(SsgState.empty)), ssg_state(slot));
}

test "state transition validation" {
    // Valid transitions
    try std.testing.expectEqual(@as(c_int, 1), ssg_can_transition(0, 1)); // empty -> content_loaded
    try std.testing.expectEqual(@as(c_int, 1), ssg_can_transition(1, 2)); // content_loaded -> built
    try std.testing.expectEqual(@as(c_int, 1), ssg_can_transition(2, 3)); // built -> previewing
    try std.testing.expectEqual(@as(c_int, 1), ssg_can_transition(3, 4)); // previewing -> ready_to_deploy
    try std.testing.expectEqual(@as(c_int, 1), ssg_can_transition(4, 5)); // ready_to_deploy -> deployed
    try std.testing.expectEqual(@as(c_int, 1), ssg_can_transition(5, 0)); // deployed -> empty
    // Invalid transitions — the key safety invariants
    try std.testing.expectEqual(@as(c_int, 0), ssg_can_transition(1, 3)); // content_loaded -> previewing (BLOCKED)
    try std.testing.expectEqual(@as(c_int, 0), ssg_can_transition(2, 5)); // built -> deployed (BLOCKED)
    try std.testing.expectEqual(@as(c_int, 0), ssg_can_transition(0, 5)); // empty -> deployed
}

// ═══════════════════════════════════════════════════════════════════════
// ADR-0006 invoke dispatch tests
// ═══════════════════════════════════════════════════════════════════════

test "invoke: each declared tool reports unavailable without changing model state" {
    ssg_reset();
    var buf: [256]u8 = undefined;
    const tools = [_][]const u8{
        "ssg_load_content",
        "ssg_build",
        "ssg_preview",
        "ssg_deploy",
        "ssg_clean",
    };
    for (tools) |t| {
        var len: usize = buf.len;
        const rc = boj_cartridge_invoke(t.ptr, "{}", &buf, &len);
        try std.testing.expectEqual(shim.RC_RUNTIME_ERROR, rc);
        try std.testing.expect(std.mem.indexOf(u8, buf[0..len], "\"success\":false") != null);
        try std.testing.expect(std.mem.indexOf(u8, buf[0..len], "\"status\":\"unavailable\"") != null);
        for (0..MAX_SITES) |i| {
            try std.testing.expectEqual(@as(c_int, @intFromEnum(SsgState.empty)), ssg_state(@intCast(i)));
        }
    }
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
    const rc = boj_cartridge_invoke("ssg_load_content", "{}", &buf, &len);
    try std.testing.expectEqual(@as(i32, -3), rc);
    try std.testing.expect(len > 4);
}
