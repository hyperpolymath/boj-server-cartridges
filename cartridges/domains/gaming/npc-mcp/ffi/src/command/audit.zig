// SPDX-License-Identifier: MPL-2.0
const std = @import("std");
const testing = std.testing;

pub const AuditEntry = struct {
    ts_ms: i64,
    tool: []const u8,
    operation_code: i32,
    decision: []const u8, // "allowed" | "denied" | "rate_limited"
    command_id: []const u8,
    result: []const u8,
};

pub const AuditLog = struct {
    allocator: std.mem.Allocator,
    file: std.fs.File,
    mutex: std.Thread.Mutex = .{},

    pub fn open(allocator: std.mem.Allocator, path: []const u8) !AuditLog {
        const file = try std.fs.createFileAbsolute(path, .{
            .truncate = false,
            .read = false,
        });
        try file.seekFromEnd(0);
        return .{ .allocator = allocator, .file = file };
    }

    pub fn close(self: *AuditLog) void {
        self.file.close();
    }

    pub fn record(self: *AuditLog, e: AuditEntry) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var line = std.ArrayList(u8){};
        defer line.deinit(self.allocator);
        try line.print(
            self.allocator,
            "{{\"ts\":{d},\"tool\":\"{s}\",\"op\":{d},\"decision\":\"{s}\",\"id\":\"{s}\",\"result\":\"{s}\"}}\n",
            .{ e.ts_ms, e.tool, e.operation_code, e.decision, e.command_id, e.result },
        );
        try self.file.writeAll(line.items);
    }
};

test "audit — writes line per call" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(path);
    const full_path = try std.fs.path.join(testing.allocator, &.{ path, "audit.log" });
    defer testing.allocator.free(full_path);

    var audit = try AuditLog.open(testing.allocator, full_path);
    defer audit.close();

    try audit.record(.{
        .ts_ms = 1000,
        .tool = "npc_say",
        .operation_code = 100,
        .decision = "allowed",
        .command_id = "cmd-1",
        .result = "ok",
    });

    const content = try tmp.dir.readFileAlloc(testing.allocator, "audit.log", 4096);
    defer testing.allocator.free(content);

    try testing.expect(std.mem.indexOf(u8, content, "npc_say") != null);
    try testing.expect(std.mem.indexOf(u8, content, "cmd-1") != null);
}
