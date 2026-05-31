// SPDX-License-Identifier: MPL-2.0
const std = @import("std");
const testing = std.testing;

pub const RawBuffer = struct {
    allocator: std.mem.Allocator,
    items: [][]u8,
    capacity: usize,
    head: usize, // index of the oldest element
    len: usize,

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !RawBuffer {
        const items = try allocator.alloc([]u8, capacity);
        return .{
            .allocator = allocator,
            .items = items,
            .capacity = capacity,
            .head = 0,
            .len = 0,
        };
    }

    pub fn deinit(self: *RawBuffer) void {
        var i: usize = 0;
        while (i < self.len) : (i += 1) {
            const idx = (self.head + i) % self.capacity;
            self.allocator.free(self.items[idx]);
        }
        self.allocator.free(self.items);
    }

    pub fn push(self: *RawBuffer, msg: []const u8) !void {
        const copy = try self.allocator.dupe(u8, msg);
        if (self.len < self.capacity) {
            const idx = (self.head + self.len) % self.capacity;
            self.items[idx] = copy;
            self.len += 1;
        } else {
            // Evict oldest
            self.allocator.free(self.items[self.head]);
            self.items[self.head] = copy;
            self.head = (self.head + 1) % self.capacity;
        }
    }

    /// Caller owns the returned slice (free with the same allocator).
    /// The inner strings are owned by the buffer — do NOT free them.
    pub fn getLast(self: *RawBuffer, alloc: std.mem.Allocator, n: usize) ![][]const u8 {
        const take = @min(n, self.len);
        var out = try alloc.alloc([]const u8, take);
        var i: usize = 0;
        while (i < take) : (i += 1) {
            const idx = (self.head + self.len - take + i) % self.capacity;
            out[i] = self.items[idx];
        }
        return out;
    }
};

test "raw buffer — push and get last N" {
    var buf = try RawBuffer.init(testing.allocator, 4);
    defer buf.deinit();

    try buf.push("msg1");
    try buf.push("msg2");
    try buf.push("msg3");

    const items = try buf.getLast(testing.allocator, 2);
    defer testing.allocator.free(items);

    try testing.expectEqual(@as(usize, 2), items.len);
    try testing.expectEqualStrings("msg2", items[0]);
    try testing.expectEqualStrings("msg3", items[1]);
}

test "raw buffer — overflows by dropping oldest" {
    var buf = try RawBuffer.init(testing.allocator, 3);
    defer buf.deinit();

    try buf.push("a");
    try buf.push("b");
    try buf.push("c");
    try buf.push("d"); // evicts "a"

    const items = try buf.getLast(testing.allocator, 3);
    defer testing.allocator.free(items);

    try testing.expectEqualStrings("b", items[0]);
    try testing.expectEqualStrings("c", items[1]);
    try testing.expectEqualStrings("d", items[2]);
}
