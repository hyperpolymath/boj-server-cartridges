// SPDX-License-Identifier: MPL-2.0
const std = @import("std");
const testing = std.testing;
const events = @import("events.zig");
const WorldState = @import("world_state.zig").WorldState;

pub fn applyPlayerJoin(ws: *WorldState, payload: events.PlayerJoinPayload, ts: i64) !void {
    try ws.upsertPlayer(.{
        .name = payload.player.name,
        .uuid = payload.player.uuid,
        .position = payload.position,
        .dimension = payload.dimension,
        .gamemode = payload.gamemode,
        .online = true,
        .last_seen_ts = ts,
    });
}

pub fn applyPlayerLeave(ws: *WorldState, player: events.PlayerRef, ts: i64) !void {
    if (ws.players.getEntry(player.name)) |entry| {
        entry.value_ptr.online = false;
        entry.value_ptr.last_seen_ts = ts;
    }
}

pub fn applyPlayerMove(ws: *WorldState, player: events.PlayerRef, pos: events.Position, dimension: []const u8, ts: i64) !void {
    if (ws.players.getEntry(player.name)) |entry| {
        entry.value_ptr.position = pos;
        entry.value_ptr.last_seen_ts = ts;
        // Note: dimension string is owned by ws, but this updates the field
        // without reallocating. Dimension changes are rare; handle via upsert if needed.
        _ = dimension;
    }
}

/// Main dispatch — takes a parsed event and applies it to the world state.
pub fn apply(ws: *WorldState, ev: *const events.ParsedEvent) !void {
    switch (ev.payload) {
        .player_join => |p| try applyPlayerJoin(ws, p, ev.ts),
        .player_leave => |ref| try applyPlayerLeave(ws, ref, ev.ts),
        .player_move => |m| try applyPlayerMove(ws, m.player, m.position, m.dimension, ev.ts),
        // Other event types: no state mutation needed for Layer 2 yet
        // (block_break affects region awareness, added in a later iteration)
        else => {},
    }
}

test "mutator — player_join upserts player as online" {
    var ws = WorldState.init(testing.allocator);
    defer ws.deinit();

    const payload: events.PlayerJoinPayload = .{
        .player = .{ .name = "Alex", .uuid = "uuid-1" },
        .position = .{ .x = 1, .y = 2, .z = 3 },
        .dimension = "minecraft:overworld",
        .gamemode = "survival",
        .first_join = true,
    };
    try applyPlayerJoin(&ws, payload, 1000);

    const p = ws.getPlayerByName("Alex") orelse return error.NotFound;
    try testing.expectEqual(true, p.online);
    try testing.expectEqual(@as(i64, 1000), p.last_seen_ts);
}

test "mutator — player_leave marks offline" {
    var ws = WorldState.init(testing.allocator);
    defer ws.deinit();

    const join_payload: events.PlayerJoinPayload = .{
        .player = .{ .name = "Alex", .uuid = "uuid-1" },
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .dimension = "o",
        .gamemode = "s",
        .first_join = false,
    };
    try applyPlayerJoin(&ws, join_payload, 1000);
    try applyPlayerLeave(&ws, .{ .name = "Alex", .uuid = "uuid-1" }, 2000);

    const p = ws.getPlayerByName("Alex") orelse return error.NotFound;
    try testing.expectEqual(false, p.online);
}
