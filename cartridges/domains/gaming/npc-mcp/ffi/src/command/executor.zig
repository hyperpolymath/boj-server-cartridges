// SPDX-License-Identifier: MPL-2.0
const std = @import("std");
const testing = std.testing;

/// A thread-safe queue of serialized JSONL commands waiting to be sent to the mod.
/// The host calls drain() (npc_drain_commands tool) when the mod polls.
pub const CommandQueue = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList([]u8),
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) CommandQueue {
        return .{
            .allocator = allocator,
            .items = std.ArrayList([]u8){},
            .mutex = .{},
        };
    }

    pub fn deinit(self: *CommandQueue) void {
        for (self.items.items) |s| self.allocator.free(s);
        self.items.deinit(self.allocator);
    }

    pub fn enqueue(self: *CommandQueue, jsonl: []const u8) !void {
        const copy = try self.allocator.dupe(u8, jsonl);
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.items.append(self.allocator, copy);
    }

    /// Caller owns returned slice AND inner strings.
    pub fn drain(self: *CommandQueue, alloc: std.mem.Allocator) ![][]u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        const out = try alloc.alloc([]u8, self.items.items.len);
        for (self.items.items, 0..) |item, i| {
            out[i] = try alloc.dupe(u8, item);
            self.allocator.free(item);
        }
        self.items.clearRetainingCapacity();
        return out;
    }
};

test "command queue — enqueue and drain" {
    var q = CommandQueue.init(testing.allocator);
    defer q.deinit();

    try q.enqueue("{\"v\":1,\"type\":\"say\",\"ts\":1,\"id\":\"cmd-1\",\"payload\":{\"message\":\"hi\",\"target\":\"@a\"}}");
    try q.enqueue("{\"v\":1,\"type\":\"give\",\"ts\":2,\"id\":\"cmd-2\",\"payload\":{\"target\":\"Alex\",\"item\":{\"id\":\"minecraft:diamond\",\"count\":1}}}");

    const drained = try q.drain(testing.allocator);
    defer {
        for (drained) |s| testing.allocator.free(s);
        testing.allocator.free(drained);
    }

    try testing.expectEqual(@as(usize, 2), drained.len);
    try testing.expect(std.mem.indexOf(u8, drained[0], "\"id\":\"cmd-1\"") != null);
}

test "command queue — drain is idempotent (second drain returns empty)" {
    var q = CommandQueue.init(testing.allocator);
    defer q.deinit();
    try q.enqueue("{\"v\":1,\"type\":\"say\",\"ts\":1,\"id\":\"cmd-x\",\"payload\":{\"message\":\"hi\"}}");

    const first = try q.drain(testing.allocator);
    for (first) |s| testing.allocator.free(s);
    testing.allocator.free(first);

    const second = try q.drain(testing.allocator);
    defer testing.allocator.free(second);
    try testing.expectEqual(@as(usize, 0), second.len);
}
