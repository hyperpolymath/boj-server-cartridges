// SPDX-License-Identifier: MPL-2.0
const std = @import("std");

pub const Position = struct { x: f64, y: f64, z: f64 };

pub const PlayerRef = struct {
    name: []const u8,
    uuid: []const u8,
};

pub const ItemStack = struct {
    id: []const u8,
    count: u32,
};

pub const EventType = enum {
    session_started,
    player_join,
    player_leave,
    player_chat,
    player_move,
    player_death,
    advancement,
    block_place,
    block_break,
    entity_spawn,
    entity_kill,
    weather_change,
    command_result,
    buffer_overflow,
    unknown,
};

pub const PlayerJoinPayload = struct {
    player: PlayerRef,
    position: Position,
    dimension: []const u8,
    gamemode: []const u8,
    first_join: bool,
};

pub const PlayerChatPayload = struct {
    player: PlayerRef,
    message: []const u8,
    addressed_to_ghost: bool,
};

pub const BlockBreakPayload = struct {
    player: PlayerRef,
    position: Position,
    dimension: []const u8,
    block: []const u8,
    tool: ?[]const u8,
};

pub const Payload = union(EventType) {
    session_started: void,
    player_join: PlayerJoinPayload,
    player_leave: PlayerRef,
    player_chat: PlayerChatPayload,
    player_move: struct { player: PlayerRef, position: Position, dimension: []const u8 },
    player_death: struct { player: PlayerRef, position: Position, cause: []const u8 },
    advancement: struct { player: PlayerRef, advancement_id: []const u8, title: []const u8 },
    block_place: struct { player: PlayerRef, position: Position, block: []const u8, dimension: []const u8 },
    block_break: BlockBreakPayload,
    entity_spawn: struct { entity_type: []const u8, position: Position, dimension: []const u8 },
    entity_kill: struct { entity_type: []const u8, position: Position, dimension: []const u8 },
    weather_change: struct { dimension: []const u8, weather: []const u8 },
    command_result: struct { command_id: []const u8, success: bool, output: ?[]const u8 },
    buffer_overflow: struct { dropped_count: u32, oldest_ts: i64, newest_ts: i64 },
    unknown: void,
};

pub const ParsedEvent = struct {
    v: u8,
    ts: i64,
    id: []const u8,
    payload: Payload,

    /// Owned strings. Call deinit to free.
    arena: std.heap.ArenaAllocator,

    pub fn deinit(self: *ParsedEvent) void {
        self.arena.deinit();
    }
};

pub fn eventTypeFromString(s: []const u8) EventType {
    const map = std.StaticStringMap(EventType).initComptime(.{
        .{ "session_started", .session_started },
        .{ "player_join", .player_join },
        .{ "player_leave", .player_leave },
        .{ "player_chat", .player_chat },
        .{ "player_move", .player_move },
        .{ "player_death", .player_death },
        .{ "advancement", .advancement },
        .{ "block_place", .block_place },
        .{ "block_break", .block_break },
        .{ "entity_spawn", .entity_spawn },
        .{ "entity_kill", .entity_kill },
        .{ "weather_change", .weather_change },
        .{ "command_result", .command_result },
        .{ "buffer_overflow", .buffer_overflow },
    });
    return map.get(s) orelse .unknown;
}

test "eventTypeFromString — known and unknown" {
    try std.testing.expectEqual(EventType.player_join, eventTypeFromString("player_join"));
    try std.testing.expectEqual(EventType.unknown, eventTypeFromString("not_a_real_event"));
}
