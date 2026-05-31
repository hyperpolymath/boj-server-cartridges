// SPDX-License-Identifier: MPL-2.0
const std = @import("std");
const testing = std.testing;
const WorldState = @import("world_state.zig").WorldState;

/// Build a JSON string describing the current world narrative.
/// Caller owns the returned memory.
pub fn synthesizeContext(alloc: std.mem.Allocator, ws: *WorldState) ![]u8 {
    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(alloc);

    var online_count: u32 = 0;
    var it = ws.players.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.online) online_count += 1;
    }

    try buf.print(alloc, "{{\"online_players\":{d},\"players\":[", .{online_count});

    var first = true;
    var it2 = ws.players.iterator();
    while (it2.next()) |entry| {
        const p = entry.value_ptr.*;
        if (!p.online) continue;
        if (!first) try buf.appendSlice(alloc, ",");
        first = false;
        try buf.print(
            alloc,
            "{{\"name\":\"{s}\",\"dimension\":\"{s}\",\"position\":[{d},{d},{d}]}}",
            .{ p.name, p.dimension, p.position.x, p.position.y, p.position.z },
        );
    }

    try buf.print(alloc, "],\"server\":{{\"tps\":{d:.1},\"weather\":\"{s}\"}}}}", .{
        ws.vitals.tps,
        ws.vitals.weather,
    });

    return buf.toOwnedSlice(alloc);
}

test "narrative — empty world produces minimal context" {
    var ws = WorldState.init(testing.allocator);
    defer ws.deinit();

    const out = try synthesizeContext(testing.allocator, &ws);
    defer testing.allocator.free(out);

    // Should include "online_players":0 somewhere
    try testing.expect(std.mem.indexOf(u8, out, "\"online_players\":0") != null);
}

test "narrative — with a player includes their name" {
    var ws = WorldState.init(testing.allocator);
    defer ws.deinit();
    try ws.upsertPlayer(.{
        .name = "Alex",
        .uuid = "u",
        .position = .{ .x = 0, .y = 64, .z = 0 },
        .dimension = "minecraft:overworld",
        .gamemode = "survival",
        .online = true,
    });

    const out = try synthesizeContext(testing.allocator, &ws);
    defer testing.allocator.free(out);

    try testing.expect(std.mem.indexOf(u8, out, "Alex") != null);
    try testing.expect(std.mem.indexOf(u8, out, "\"online_players\":1") != null);
}
