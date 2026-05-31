// SPDX-License-Identifier: MPL-2.0
const std = @import("std");
const testing = std.testing;

const READ_ONLY_TOOLS = [_][]const u8{
    "npc_get_raw_events",
    "npc_get_recent_events",
    "npc_subscribe_events",
    "npc_get_world_state",
    "npc_get_player_state",
    "npc_query_region",
    "npc_get_narrative_context",
    "npc_get_player_profile",
};

pub const PersonaPermissions = struct {
    allowed_patterns: [][]const u8,
    denied_patterns: [][]const u8,
    max_commands_per_minute: u32,
    max_blocks_per_fill: u32,
};

pub const Persona = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    name: []const u8,
    visibility: []const u8,
    permissions: PersonaPermissions,

    pub fn deinit(self: *Persona) void {
        self.arena.deinit();
    }

    /// Parses JSON into a persona. Everything is allocated in an arena
    /// owned by the returned Persona. Caller must call deinit().
    pub fn fromJsonLeaky(alloc: std.mem.Allocator, json_text: []const u8) !Persona {
        var arena = std.heap.ArenaAllocator.init(alloc);
        errdefer arena.deinit();
        const aa = arena.allocator();

        const root = try std.json.parseFromSliceLeaky(std.json.Value, aa, json_text, .{});
        if (root != .object) return error.BadPersonaJson;

        const name = (root.object.get("name") orelse return error.MissingName).string;
        const visibility = (root.object.get("visibility") orelse return error.MissingVisibility).string;

        const perms_val = root.object.get("permissions") orelse return error.MissingPermissions;
        if (perms_val != .object) return error.MissingPermissions;

        const allowed = try patternsFromArray(aa, perms_val.object.get("allowed_tools"));
        const denied = try patternsFromArray(aa, perms_val.object.get("denied_tools"));
        const max_cmds = @as(u32, @intCast((perms_val.object.get("max_commands_per_minute") orelse return error.MissingField).integer));
        const max_fill = @as(u32, @intCast((perms_val.object.get("max_blocks_per_fill") orelse return error.MissingField).integer));

        return .{
            .allocator = alloc,
            .arena = arena,
            .name = try aa.dupe(u8, name),
            .visibility = try aa.dupe(u8, visibility),
            .permissions = .{
                .allowed_patterns = allowed,
                .denied_patterns = denied,
                .max_commands_per_minute = max_cmds,
                .max_blocks_per_fill = max_fill,
            },
        };
    }

    fn patternsFromArray(aa: std.mem.Allocator, val: ?std.json.Value) ![][]const u8 {
        if (val == null or val.? != .array) return try aa.alloc([]const u8, 0);
        const items = val.?.array.items;
        var out = try aa.alloc([]const u8, items.len);
        for (items, 0..) |item, i| {
            out[i] = try aa.dupe(u8, item.string);
        }
        return out;
    }

    pub fn isToolAllowed(self: *const Persona, tool: []const u8) bool {
        // Rule 1: read-only tools always allowed
        for (READ_ONLY_TOOLS) |ro| {
            if (std.mem.eql(u8, ro, tool)) return true;
        }
        // Rule 2: denylist wins
        for (self.permissions.denied_patterns) |pat| {
            if (globMatch(pat, tool)) return false;
        }
        // Rule 3: allowlist grants
        for (self.permissions.allowed_patterns) |pat| {
            if (globMatch(pat, tool)) return true;
        }
        // Rule 4: default deny
        return false;
    }
};

/// Tiny glob matcher — supports only trailing `*`, which is all the persona needs.
fn globMatch(pattern: []const u8, s: []const u8) bool {
    if (pattern.len > 0 and pattern[pattern.len - 1] == '*') {
        const prefix = pattern[0 .. pattern.len - 1];
        return std.mem.startsWith(u8, s, prefix);
    }
    return std.mem.eql(u8, pattern, s);
}

test "persona — allowlist grants, denylist revokes" {
    var p = try Persona.fromJsonLeaky(testing.allocator,
        \\{
        \\  "name": "Test",
        \\  "visibility": "overt",
        \\  "permissions": {
        \\    "allowed_tools": ["npc_say", "npc_give"],
        \\    "denied_tools": ["npc_execute_command"],
        \\    "max_commands_per_minute": 60,
        \\    "max_blocks_per_fill": 100
        \\  }
        \\}
    );
    defer p.deinit();

    try testing.expect(p.isToolAllowed("npc_say"));
    try testing.expect(p.isToolAllowed("npc_give"));
    try testing.expect(!p.isToolAllowed("npc_execute_command"));
    try testing.expect(!p.isToolAllowed("npc_tp")); // not in allowlist
}

test "persona — read-only tools always allowed regardless" {
    var p = try Persona.fromJsonLeaky(testing.allocator,
        \\{"name":"T","visibility":"overt","permissions":{"allowed_tools":[],"denied_tools":["npc_get_world_state"],"max_commands_per_minute":60,"max_blocks_per_fill":1}}
    );
    defer p.deinit();

    // Even though denied explicitly, read-only tools pass.
    try testing.expect(p.isToolAllowed("npc_get_world_state"));
}

test "persona — glob patterns in allowlist" {
    var p = try Persona.fromJsonLeaky(testing.allocator,
        \\{"name":"T","visibility":"overt","permissions":{"allowed_tools":["npc_get_*","npc_say"],"denied_tools":[],"max_commands_per_minute":60,"max_blocks_per_fill":1}}
    );
    defer p.deinit();

    try testing.expect(p.isToolAllowed("npc_get_world_state"));
    try testing.expect(p.isToolAllowed("npc_get_player_state"));
    try testing.expect(p.isToolAllowed("npc_say"));
    try testing.expect(!p.isToolAllowed("npc_tp"));
}
