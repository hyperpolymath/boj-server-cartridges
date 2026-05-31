// SPDX-License-Identifier: MPL-2.0
// NPC-MCP cartridge root — C ABI surface, driven by the cartridge FFI dispatch (npc_mcp_ffi.zig).
const std = @import("std");

pub const raw_buffer = @import("perception/raw_buffer.zig");
pub const events = @import("perception/events.zig");
pub const parser = @import("perception/parser.zig");
pub const world_state = @import("perception/world_state.zig");
pub const state_mutator = @import("perception/state_mutator.zig");
pub const narrative = @import("perception/narrative.zig");
pub const executor = @import("command/executor.zig");
pub const rate_limiter = @import("command/rate_limiter.zig");
pub const audit = @import("command/audit.zig");
pub const persona = @import("persona.zig");

// ═══════════════════════════════════════════════════════════════════════
// Global singleton — initialized by npc_init, lives for the lifetime of the
// V-lang adapter process. Access guarded by mutex.
// ═══════════════════════════════════════════════════════════════════════

const Global = struct {
    allocator: std.mem.Allocator,
    raw: raw_buffer.RawBuffer,
    state: world_state.WorldState,
    queue: executor.CommandQueue,
    limiter: rate_limiter.RateLimiter,
    audit_log: ?audit.AuditLog,
    persona_value: ?persona.Persona,
    mutex: std.Thread.Mutex,
};

// Zig 0.15.2: std.heap.GeneralPurposeAllocator was removed; use DebugAllocator instead.
var g_allocator: std.heap.DebugAllocator(.{}) = .init;
var g: ?Global = null;

fn state() *Global {
    return &(g orelse @panic("npc_init not called"));
}

// ═══════════════════════════════════════════════════════════════════════
// Lifecycle
// ═══════════════════════════════════════════════════════════════════════

/// Initialize the cartridge. Returns 0 on success, nonzero on error.
pub export fn npc_init() callconv(.c) i32 {
    const alloc = g_allocator.allocator();
    const raw = raw_buffer.RawBuffer.init(alloc, 10_000) catch return -1;
    g = .{
        .allocator = alloc,
        .raw = raw,
        .state = world_state.WorldState.init(alloc),
        .queue = executor.CommandQueue.init(alloc),
        .limiter = rate_limiter.RateLimiter.init(.{ .rate_per_sec = 1.0, .burst = 60 }),
        .audit_log = null,
        .persona_value = null,
        .mutex = .{},
    };
    return 0;
}

pub export fn npc_shutdown() callconv(.c) i32 {
    if (g) |*gg| {
        gg.raw.deinit();
        gg.state.deinit();
        gg.queue.deinit();
        if (gg.audit_log) |*a| a.close();
        if (gg.persona_value) |*p| p.deinit();
        g = null;
    }
    _ = g_allocator.deinit();
    return 0;
}

// ═══════════════════════════════════════════════════════════════════════
// Event intake
// ═══════════════════════════════════════════════════════════════════════

/// Called via the npc_ingest_event tool when the Fabric mod POSTs a JSONL event.
/// `ptr`/`len` is a UTF-8 slice. Returns 0 on success, nonzero on malformed input.
pub export fn npc_ingest_event(ptr: [*]const u8, len: usize) callconv(.c) i32 {
    const gg = state();
    gg.mutex.lock();
    defer gg.mutex.unlock();

    const slice = ptr[0..len];
    gg.raw.push(slice) catch return -1;

    var parsed = parser.parse(gg.allocator, slice) catch return -2;
    defer parsed.deinit();

    state_mutator.apply(&gg.state, &parsed) catch return -3;
    return 0;
}

// ═══════════════════════════════════════════════════════════════════════
// Perception queries
// ═══════════════════════════════════════════════════════════════════════

/// Synthesize current narrative context.
/// The returned pointer is a null-terminated C string allocated with the
/// global allocator; caller must call `npc_free_string` to release.
pub export fn npc_narrative_context() callconv(.c) [*:0]const u8 {
    const gg = state();
    gg.mutex.lock();
    defer gg.mutex.unlock();

    const json = narrative.synthesizeContext(gg.allocator, &gg.state) catch {
        return "{\"error\":\"synthesis_failed\"}";
    };
    const with_null = gg.allocator.allocSentinel(u8, json.len, 0) catch {
        gg.allocator.free(json);
        return "{\"error\":\"oom\"}";
    };
    @memcpy(with_null[0..json.len], json);
    gg.allocator.free(json);
    return with_null.ptr;
}

/// Return the last `count` raw JSONL events as a JSON array.
/// Caller must call npc_free_string to release the returned pointer.
pub export fn npc_get_raw_events(count: usize) callconv(.c) [*:0]const u8 {
    const gg = state();
    gg.mutex.lock();
    defer gg.mutex.unlock();

    const items = gg.raw.getLast(gg.allocator, count) catch {
        return "[]";
    };
    defer gg.allocator.free(items);

    var out = std.ArrayList(u8){};
    out.append(gg.allocator, '[') catch return "[]";
    for (items, 0..) |item, i| {
        if (i > 0) out.append(gg.allocator, ',') catch return "[]";
        out.appendSlice(gg.allocator, item) catch return "[]";
    }
    out.append(gg.allocator, ']') catch return "[]";

    const owned = out.toOwnedSlice(gg.allocator) catch return "[]";
    const sentinel = gg.allocator.allocSentinel(u8, owned.len, 0) catch {
        gg.allocator.free(owned);
        return "[]";
    };
    @memcpy(sentinel[0..owned.len], owned);
    gg.allocator.free(owned);
    return sentinel.ptr;
}

pub export fn npc_free_string(s: [*:0]const u8) callconv(.c) void {
    const gg = state();
    const slice = std.mem.span(s);
    gg.allocator.free(slice);
}

// ═══════════════════════════════════════════════════════════════════════
// Command submission
// ═══════════════════════════════════════════════════════════════════════

/// Enqueue a command for delivery to the mod. Returns 0 on success.
pub export fn npc_enqueue_command(ptr: [*]const u8, len: usize) callconv(.c) i32 {
    const gg = state();
    const now_ns = std.time.nanoTimestamp();
    if (!gg.limiter.tryAcquire(@intCast(now_ns))) return -1;
    gg.queue.enqueue(ptr[0..len]) catch return -2;
    return 0;
}

/// Drain pending commands. Writes a newline-delimited concatenation into a
/// newly-allocated buffer and returns it as a null-terminated string.
/// Caller must call npc_free_string.
pub export fn npc_drain_commands() callconv(.c) [*:0]const u8 {
    const gg = state();
    const items = gg.queue.drain(gg.allocator) catch return "";
    defer {
        for (items) |s| gg.allocator.free(s);
        gg.allocator.free(items);
    }

    // Zig 0.15.2: std.ArrayList(u8) is unmanaged — use .{} init and pass allocator to each method.
    var out = std.ArrayList(u8){};
    for (items) |item| {
        out.appendSlice(gg.allocator, item) catch return "";
        out.append(gg.allocator, '\n') catch return "";
    }
    const owned = out.toOwnedSlice(gg.allocator) catch return "";

    const sentinel = gg.allocator.allocSentinel(u8, owned.len, 0) catch {
        gg.allocator.free(owned);
        return "";
    };
    @memcpy(sentinel[0..owned.len], owned);
    gg.allocator.free(owned);
    return sentinel.ptr;
}

// ═══════════════════════════════════════════════════════════════════════
// Persona
// ═══════════════════════════════════════════════════════════════════════

pub export fn npc_load_persona_json(ptr: [*]const u8, len: usize) callconv(.c) i32 {
    const gg = state();
    gg.mutex.lock();
    defer gg.mutex.unlock();

    const new_persona = persona.Persona.fromJsonLeaky(gg.allocator, ptr[0..len]) catch return -1;
    if (gg.persona_value) |*old| old.deinit();
    gg.persona_value = new_persona;
    return 0;
}

pub export fn npc_is_tool_allowed(ptr: [*]const u8, len: usize) callconv(.c) i32 {
    const gg = state();
    gg.mutex.lock();
    defer gg.mutex.unlock();

    const p = if (gg.persona_value) |*pp| pp else return -1; // no persona loaded
    return if (p.isToolAllowed(ptr[0..len])) 1 else 0;
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
