// SPDX-License-Identifier: MPL-2.0
const std = @import("std");
const testing = std.testing;
const events = @import("events.zig");

pub const TrackedPlayer = struct {
    name: []const u8,
    uuid: []const u8,
    position: events.Position,
    dimension: []const u8,
    gamemode: []const u8,
    online: bool,
    last_seen_ts: i64 = 0,
};

pub const ServerVitals = struct {
    tps: f32 = 20.0,
    player_count: u32 = 0,
    day_time: i64 = 0,
    weather: []const u8 = "clear",
};

/// In-memory world state model. All strings are owned by the state — when
/// an entry is replaced or removed, the old strings are freed.
pub const WorldState = struct {
    allocator: std.mem.Allocator,
    players: std.StringHashMap(TrackedPlayer),
    vitals: ServerVitals,

    pub fn init(allocator: std.mem.Allocator) WorldState {
        return .{
            .allocator = allocator,
            .players = std.StringHashMap(TrackedPlayer).init(allocator),
            .vitals = .{},
        };
    }

    pub fn deinit(self: *WorldState) void {
        var it = self.players.iterator();
        while (it.next()) |entry| {
            self.freePlayer(entry.value_ptr.*);
            self.allocator.free(entry.key_ptr.*);
        }
        self.players.deinit();
    }

    /// Free all player-owned strings except .name, which is shared with the
    /// map key and freed separately (either via entry.key_ptr.* in deinit, or
    /// left as-is when re-using the existing key on upsert).
    fn freePlayer(self: *WorldState, p: TrackedPlayer) void {
        self.allocator.free(p.uuid);
        self.allocator.free(p.dimension);
        self.allocator.free(p.gamemode);
    }

    pub fn upsertPlayer(self: *WorldState, p: TrackedPlayer) !void {
        if (self.players.getEntry(p.name)) |existing| {
            // Key already in map — reuse the existing owned key slice for
            // .name so we don't introduce a second allocation that would leak.
            const existing_name = existing.key_ptr.*;
            self.freePlayer(existing.value_ptr.*);
            existing.value_ptr.* = .{
                .name = existing_name,
                .uuid = try self.allocator.dupe(u8, p.uuid),
                .position = p.position,
                .dimension = try self.allocator.dupe(u8, p.dimension),
                .gamemode = try self.allocator.dupe(u8, p.gamemode),
                .online = p.online,
                .last_seen_ts = p.last_seen_ts,
            };
            return;
        }

        const name_copy = try self.allocator.dupe(u8, p.name);
        errdefer self.allocator.free(name_copy);

        const stored: TrackedPlayer = .{
            .name = name_copy,
            .uuid = try self.allocator.dupe(u8, p.uuid),
            .position = p.position,
            .dimension = try self.allocator.dupe(u8, p.dimension),
            .gamemode = try self.allocator.dupe(u8, p.gamemode),
            .online = p.online,
            .last_seen_ts = p.last_seen_ts,
        };
        try self.players.put(name_copy, stored);
    }

    pub fn getPlayerByName(self: *WorldState, name: []const u8) ?TrackedPlayer {
        return self.players.get(name);
    }

    pub fn markOffline(self: *WorldState, name: []const u8) !void {
        if (self.players.getEntry(name)) |entry| {
            entry.value_ptr.online = false;
        }
    }
};

test "world state — player registry add and lookup" {
    var ws = WorldState.init(testing.allocator);
    defer ws.deinit();

    try ws.upsertPlayer(.{
        .name = "Alex",
        .uuid = "069a79f4-44e9-4726-a5be-fca90e38aaf5",
        .position = .{ .x = 10, .y = 64, .z = -20 },
        .dimension = "minecraft:overworld",
        .gamemode = "survival",
        .online = true,
    });

    const player = ws.getPlayerByName("Alex") orelse return error.NotFound;
    try testing.expectEqual(@as(f64, 10), player.position.x);
    try testing.expectEqualStrings("minecraft:overworld", player.dimension);
}

test "world state — remove player on leave" {
    var ws = WorldState.init(testing.allocator);
    defer ws.deinit();
    try ws.upsertPlayer(.{
        .name = "Alex",
        .uuid = "x",
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .dimension = "o",
        .gamemode = "s",
        .online = true,
    });
    try ws.markOffline("Alex");
    const p = ws.getPlayerByName("Alex") orelse return error.NotFound;
    try testing.expectEqual(false, p.online);
}
