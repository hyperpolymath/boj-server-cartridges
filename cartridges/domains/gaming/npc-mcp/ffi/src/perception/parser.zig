// SPDX-License-Identifier: MPL-2.0
const std = @import("std");
const testing = std.testing;
const events = @import("events.zig");

pub const ParseError = error{
    UnsupportedProtocolVersion,
    MalformedEnvelope,
    MissingField,
    WrongFieldType,
    OutOfMemory,
};

/// Parse a single JSONL message into a ParsedEvent.
/// The returned event owns an arena; caller must call deinit().
pub fn parse(alloc: std.mem.Allocator, input: []const u8) !events.ParsedEvent {
    var arena = std.heap.ArenaAllocator.init(alloc);
    errdefer arena.deinit();
    const aa = arena.allocator();

    const root = try std.json.parseFromSliceLeaky(
        std.json.Value,
        aa,
        input,
        .{},
    );

    if (root != .object) return ParseError.MalformedEnvelope;
    const obj = root.object;

    const v_val = obj.get("v") orelse return ParseError.MissingField;
    if (v_val != .integer) return ParseError.WrongFieldType;
    if (v_val.integer != 1) return ParseError.UnsupportedProtocolVersion;

    const type_val = obj.get("type") orelse return ParseError.MissingField;
    if (type_val != .string) return ParseError.WrongFieldType;

    const ts_val = obj.get("ts") orelse return ParseError.MissingField;
    if (ts_val != .integer) return ParseError.WrongFieldType;

    const id_val = obj.get("id") orelse return ParseError.MissingField;
    if (id_val != .string) return ParseError.WrongFieldType;

    const payload_val = obj.get("payload") orelse return ParseError.MissingField;
    if (payload_val != .object) return ParseError.WrongFieldType;

    const etype = events.eventTypeFromString(type_val.string);
    const payload: events.Payload = switch (etype) {
        .player_join => .{ .player_join = try parsePlayerJoin(aa, payload_val.object) },
        .player_chat => .{ .player_chat = try parsePlayerChat(aa, payload_val.object) },
        .block_break => .{ .block_break = try parseBlockBreak(aa, payload_val.object) },
        .player_leave => .{ .player_leave = try parsePlayerRef(aa, payload_val.object, "player") },
        .unknown => .{ .unknown = {} },
        else => .{ .unknown = {} }, // other types handled similarly — stubbed for first cut
    };

    return events.ParsedEvent{
        .v = @intCast(v_val.integer),
        .ts = ts_val.integer,
        .id = try aa.dupe(u8, id_val.string),
        .payload = payload,
        .arena = arena,
    };
}

fn parsePosition(obj: std.json.ObjectMap, key: []const u8) !events.Position {
    const val = obj.get(key) orelse return ParseError.MissingField;
    if (val != .array or val.array.items.len != 3) return ParseError.WrongFieldType;
    const xs = val.array.items;
    return .{
        .x = xs[0].float,
        .y = xs[1].float,
        .z = xs[2].float,
    };
}

fn parsePlayerRef(aa: std.mem.Allocator, obj: std.json.ObjectMap, key: []const u8) !events.PlayerRef {
    const val = obj.get(key) orelse return ParseError.MissingField;
    if (val != .object) return ParseError.WrongFieldType;
    const name_v = val.object.get("name") orelse return ParseError.MissingField;
    const uuid_v = val.object.get("uuid") orelse return ParseError.MissingField;
    return .{
        .name = try aa.dupe(u8, name_v.string),
        .uuid = try aa.dupe(u8, uuid_v.string),
    };
}

fn parsePlayerJoin(aa: std.mem.Allocator, obj: std.json.ObjectMap) !events.PlayerJoinPayload {
    return .{
        .player = try parsePlayerRef(aa, obj, "player"),
        .position = try parsePosition(obj, "position"),
        .dimension = try aa.dupe(u8, (obj.get("dimension") orelse return ParseError.MissingField).string),
        .gamemode = try aa.dupe(u8, (obj.get("gamemode") orelse return ParseError.MissingField).string),
        .first_join = if (obj.get("first_join")) |v| v.bool else false,
    };
}

fn parsePlayerChat(aa: std.mem.Allocator, obj: std.json.ObjectMap) !events.PlayerChatPayload {
    return .{
        .player = try parsePlayerRef(aa, obj, "player"),
        .message = try aa.dupe(u8, (obj.get("message") orelse return ParseError.MissingField).string),
        .addressed_to_ghost = if (obj.get("addressed_to_ghost")) |v| v.bool else false,
    };
}

fn parseBlockBreak(aa: std.mem.Allocator, obj: std.json.ObjectMap) !events.BlockBreakPayload {
    return .{
        .player = try parsePlayerRef(aa, obj, "player"),
        .position = try parsePosition(obj, "position"),
        .dimension = try aa.dupe(u8, (obj.get("dimension") orelse return ParseError.MissingField).string),
        .block = try aa.dupe(u8, (obj.get("block") orelse return ParseError.MissingField).string),
        .tool = if (obj.get("tool")) |v| try aa.dupe(u8, v.string) else null,
    };
}

test "parser — player_join valid envelope" {
    const input =
        \\{"v":1,"type":"player_join","ts":1735948800000,"id":"evt-001","payload":{"player":{"name":"Alex","uuid":"069a79f4-44e9-4726-a5be-fca90e38aaf5"},"position":[0.5,64.0,0.5],"dimension":"minecraft:overworld","gamemode":"survival","first_join":true}}
    ;
    var parsed = try parse(testing.allocator, input);
    defer parsed.deinit();

    try testing.expectEqual(@as(u8, 1), parsed.v);
    try testing.expectEqualStrings("evt-001", parsed.id);

    switch (parsed.payload) {
        .player_join => |pj| {
            try testing.expectEqualStrings("Alex", pj.player.name);
            try testing.expectEqualStrings("minecraft:overworld", pj.dimension);
            try testing.expectEqual(true, pj.first_join);
        },
        else => return error.WrongEventType,
    }
}

test "parser — unknown event type yields .unknown" {
    const input =
        \\{"v":1,"type":"nonexistent","ts":1,"id":"x","payload":{}}
    ;
    var parsed = try parse(testing.allocator, input);
    defer parsed.deinit();
    try testing.expectEqual(events.EventType.unknown, std.meta.activeTag(parsed.payload));
}

test "parser — rejects wrong protocol version" {
    const input =
        \\{"v":2,"type":"player_join","ts":1,"id":"x","payload":{}}
    ;
    const err = parse(testing.allocator, input);
    try testing.expectError(error.UnsupportedProtocolVersion, err);
}
