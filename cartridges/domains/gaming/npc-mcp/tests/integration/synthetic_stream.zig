// SPDX-License-Identifier: MPL-2.0
// End-to-end test: feed a synthetic JSONL stream through the parser and state
// mutator, then verify the narrative layer sees the expected world.
const std = @import("std");
const testing = std.testing;
const root = @import("npcmcp");

test "synthetic stream — two players join and one leaves" {
    const alloc = testing.allocator;

    var ws = root.world_state.WorldState.init(alloc);
    defer ws.deinit();

    // Positions use float literals so the JSON parser yields .float values,
    // matching parsePosition's xs[i].float access in perception/parser.zig.
    const stream = [_][]const u8{
        \\{"v":1,"type":"player_join","ts":1000,"id":"e1","payload":{"player":{"name":"Alex","uuid":"u-alex"},"position":[0.0,64.0,0.0],"dimension":"minecraft:overworld","gamemode":"survival","first_join":true}}
        ,
        \\{"v":1,"type":"player_join","ts":2000,"id":"e2","payload":{"player":{"name":"Sam","uuid":"u-sam"},"position":[10.0,64.0,10.0],"dimension":"minecraft:overworld","gamemode":"creative","first_join":false}}
        ,
        \\{"v":1,"type":"player_leave","ts":3000,"id":"e3","payload":{"player":{"name":"Alex","uuid":"u-alex"}}}
    };

    for (stream) |line| {
        var parsed = try root.parser.parse(alloc, line);
        defer parsed.deinit();
        try root.state_mutator.apply(&ws, &parsed);
    }

    const alex = ws.getPlayerByName("Alex") orelse return error.MissingAlex;
    try testing.expectEqual(false, alex.online);

    const sam = ws.getPlayerByName("Sam") orelse return error.MissingSam;
    try testing.expectEqual(true, sam.online);

    const narr = try root.narrative.synthesizeContext(alloc, &ws);
    defer alloc.free(narr);

    // Only Sam should appear in the online roster.
    try testing.expect(std.mem.indexOf(u8, narr, "Sam") != null);
    try testing.expect(std.mem.indexOf(u8, narr, "\"online_players\":1") != null);
}
