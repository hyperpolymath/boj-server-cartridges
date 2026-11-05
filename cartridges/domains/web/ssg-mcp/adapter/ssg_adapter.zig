// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// ssg-mcp/adapter/ssg_adapter.zig
//
// Three-protocol BoJ adapter: REST (port 9292), gRPC-compat (port 9293),
// GraphQL (port 9294).
// The transport exists, but no SSG backend is wired into native dispatch.

const std = @import("std");
const ffi = @import("ssg_ffi");

const REST_PORT: u16 = 9292;
const GRPC_PORT: u16 = 9293;
const GQL_PORT: u16 = 9294;

const Response = struct { status: u16, body: []const u8 };

fn errJson(buf: []u8, msg: []const u8) []u8 {
    return std.fmt.bufPrint(buf, "{{\"success\":false,\"error\":\"{s}\"}}", .{msg}) catch buf[0..0];
}

/// Return 503 for recognised SSG tools and 404 for unknown tools; the request
/// body is ignored. The response body uses `resp` and is empty if it is too small.
fn dispatch(tool: []const u8, _body: []const u8, resp: []u8) Response {
    _ = _body;
    if (std.mem.eql(u8, tool, "ssg_load_content") or
        std.mem.eql(u8, tool, "ssg_build") or
        std.mem.eql(u8, tool, "ssg_preview") or
        std.mem.eql(u8, tool, "ssg_deploy") or
        std.mem.eql(u8, tool, "ssg_clean"))
    {
        return .{ .status = 503, .body = errJson(resp, "ssg-mcp native backend is not implemented") };
    }
    return .{ .status = 404, .body = errJson(resp, "unknown tool") };
}

fn dispatchRest(path: []const u8, body: []const u8, resp: []u8) Response {
    // Expect /tools/<tool_name>
    const prefix = "/tools/";
    if (std.mem.startsWith(u8, path, prefix)) {
        const tool = path[prefix.len..];
        return dispatch(tool, body, resp);
    }
    return .{ .status = 404, .body = errJson(resp, "not found") };
}

fn dispatchGrpc(path: []const u8, body: []const u8, resp: []u8) Response {
    // Expect /<Service>/<Method> — derive tool from Method
    var it = std.mem.splitScalar(u8, path, '/');
    _ = it.next(); // leading empty
    _ = it.next(); // service
    const method = it.next() orelse return .{ .status = 404, .body = errJson(resp, "bad gRPC path") };
    return dispatch(method, body, resp);
}

// This is a conservative selector for the unavailable native endpoint, not a
// GraphQL executor or schema validator. Only one operation and one root field
// are accepted; comments, aliases and strings cannot supply that field name.
const GraphqlCursor = struct {
    source: []const u8,
    pos: usize = 0,

    fn ignored(self: *GraphqlCursor) void {
        while (self.pos < self.source.len) {
            const ch = self.source[self.pos];
            if (std.ascii.isWhitespace(ch) or ch == ',') {
                self.pos += 1;
            } else if (ch == '#') {
                while (self.pos < self.source.len and self.source[self.pos] != '\n' and self.source[self.pos] != '\r')
                    self.pos += 1;
            } else break;
        }
    }

    fn take(self: *GraphqlCursor, ch: u8) bool {
        self.ignored();
        if (self.pos == self.source.len or self.source[self.pos] != ch) return false;
        self.pos += 1;
        return true;
    }

    fn name(self: *GraphqlCursor) ?[]const u8 {
        self.ignored();
        const start = self.pos;
        if (start == self.source.len) return null;
        const first = self.source[start];
        if (first != '_' and !std.ascii.isAlphabetic(first)) return null;
        self.pos += 1;
        while (self.pos < self.source.len) : (self.pos += 1) {
            const ch = self.source[self.pos];
            if (ch != '_' and !std.ascii.isAlphanumeric(ch)) break;
        }
        return self.source[start..self.pos];
    }

    fn string(self: *GraphqlCursor) bool {
        if (std.mem.startsWith(u8, self.source[self.pos..], "\"\"\"")) {
            self.pos += 3;
            while (self.pos < self.source.len) {
                if (std.mem.startsWith(u8, self.source[self.pos..], "\\\"\"\"")) {
                    self.pos += 4;
                } else if (std.mem.startsWith(u8, self.source[self.pos..], "\"\"\"")) {
                    self.pos += 3;
                    return true;
                } else self.pos += 1;
            }
            return false;
        }
        self.pos += 1; // Opening quote.
        while (self.pos < self.source.len) {
            const ch = self.source[self.pos];
            self.pos += 1;
            if (ch == '"') return true;
            if (ch < 0x20) return false;
            if (ch == '\\') {
                if (self.pos == self.source.len or self.source[self.pos] < 0x20) return false;
                self.pos += 1;
            }
        }
        return false;
    }

    fn group(self: *GraphqlCursor, open: u8) bool {
        if (!self.take(open)) return false;
        var expected: [64]u8 = undefined;
        expected[0] = if (open == '(') ')' else '}';
        var depth: usize = 1;
        while (depth != 0) {
            self.ignored();
            if (self.pos == self.source.len) return false;
            const ch = self.source[self.pos];
            if (ch == '"') {
                if (!self.string()) return false;
                continue;
            }
            self.pos += 1;
            switch (ch) {
                '(', '{', '[' => {
                    if (depth == expected.len) return false;
                    expected[depth] = switch (ch) {
                        '(' => ')',
                        '{' => '}',
                        else => ']',
                    };
                    depth += 1;
                },
                ')', '}', ']' => {
                    if (ch != expected[depth - 1]) return false;
                    depth -= 1;
                },
                else => {},
            }
        }
        return true;
    }

    fn optionalGroup(self: *GraphqlCursor, open: u8) bool {
        self.ignored();
        if (self.pos == self.source.len or self.source[self.pos] != open) return true;
        return self.group(open);
    }
};

fn selectedGraphqlTool(document: []const u8, operation_name: ?[]const u8) ?[]const u8 {
    var cursor: GraphqlCursor = .{ .source = document };
    cursor.ignored();
    if (cursor.pos == document.len) return null;
    var declared_name: ?[]const u8 = null;
    if (document[cursor.pos] != '{') {
        const operation = cursor.name() orelse return null;
        if (!std.mem.eql(u8, operation, "query") and !std.mem.eql(u8, operation, "mutation")) return null;
        declared_name = cursor.name();
        if (!cursor.optionalGroup('(')) return null;
    }
    if (operation_name) |requested| {
        const declared = declared_name orelse return null;
        if (!std.mem.eql(u8, requested, declared)) return null;
    }
    if (!cursor.take('{')) return null;
    var field = cursor.name() orelse return null;
    if (cursor.take(':')) field = cursor.name() orelse return null;
    if (!cursor.optionalGroup('(') or !cursor.optionalGroup('{')) return null;
    if (!cursor.take('}')) return null;
    cursor.ignored();
    if (cursor.pos != document.len) return null;
    return field;
}

fn dispatchGraphqlDocument(document: []const u8, operation_name: ?[]const u8, resp: []u8) Response {
    if (selectedGraphqlTool(document, operation_name)) |tool| {
        const response = dispatch(tool, document, resp);
        if (response.status == 503) return response;
    }
    return .{ .status = 400, .body = errJson(resp, "unrecognised or unsupported GraphQL operation") };
}

fn dispatchGraphql(body: []const u8, resp: []u8) Response {
    // Accept a JSON request envelope or a raw document. Invalid JSON cannot
    // supply a field through quoted keys: the raw selector requires a Name.
    const parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, body, .{}) catch
        return dispatchGraphqlDocument(body, null, resp);
    defer parsed.deinit();
    if (parsed.value == .object) {
        const query = parsed.value.object.get("query");
        const selected = parsed.value.object.get("operationName");
        if (query) |document| {
            if (document == .string) {
                if (selected) |operation| {
                    if (operation == .string and operation.string.len != 0)
                        return dispatchGraphqlDocument(document.string, operation.string, resp);
                    if (operation != .null)
                        return .{ .status = 400, .body = errJson(resp, "invalid GraphQL operationName") };
                }
                return dispatchGraphqlDocument(document.string, null, resp);
            }
        }
    }
    return .{ .status = 400, .body = errJson(resp, "invalid GraphQL request envelope") };
}

test "all SSG operations are unavailable on each native protocol" {
    const tools = [_][]const u8{ "ssg_load_content", "ssg_build", "ssg_preview", "ssg_deploy", "ssg_clean" };
    var response: [256]u8 = undefined;
    var path: [128]u8 = undefined;
    for (tools) |tool| {
        const rest_path = try std.fmt.bufPrint(&path, "/tools/{s}", .{tool});
        const rest = dispatchRest(rest_path, "{}", &response);
        try std.testing.expectEqual(@as(u16, 503), rest.status);
        try std.testing.expect(std.mem.indexOf(u8, rest.body, "\"success\":false") != null);

        const grpc_path = try std.fmt.bufPrint(&path, "/Ssg/{s}", .{tool});
        const grpc = dispatchGrpc(grpc_path, "{}", &response);
        try std.testing.expectEqual(@as(u16, 503), grpc.status);

        const document = try std.fmt.bufPrint(&path, "{{ {s} }}", .{tool});
        const graphql = dispatchGraphql(document, &response);
        try std.testing.expectEqual(@as(u16, 503), graphql.status);
    }
}

test "unknown operations remain distinct from an unavailable backend" {
    var response: [256]u8 = undefined;
    try std.testing.expectEqual(@as(u16, 404), dispatchRest("/tools/unknown", "{}", &response).status);
    try std.testing.expectEqual(@as(u16, 404), dispatchGrpc("/Ssg/unknown", "{}", &response).status);
    try std.testing.expectEqual(@as(u16, 400), dispatchGraphql("unknown", &response).status);
}

test "GraphQL dispatch selects the field rather than comments strings or aliases" {
    var response: [256]u8 = undefined;
    const unknown = [_][]const u8{
        "{ unknown } # ssg_build",
        "{ unknown(note: \"ssg_build\") }",
        "{ ssg_build: unknown }",
        "{ ssg_build_extra }",
        "query ssg_build { unknown }",
        "{\"query\":\"{ unknown }\",\"variables\":{\"tool\":\"ssg_build\"}}",
    };
    for (unknown) |document|
        try std.testing.expectEqual(@as(u16, 400), dispatchGraphql(document, &response).status);
}

test "GraphQL recognises one named selected tool in raw and JSON requests" {
    var response: [256]u8 = undefined;
    const recognised = [_][]const u8{
        "# unknown ssg_deploy\n{ result: ssg_build }",
        "mutation Build($id: ID!) { result: ssg_build(session_id: $id) { success } }",
        "{ ssg_build(options: {note: \"} unknown {\", nested: [1, 2]}) { success } }",
        "{\"query\":\"query Build { ssg_build }\",\"operationName\":\"Build\"}",
        "{\"query\":\"{ ssg_build }\",\"operationName\":null}",
    };
    for (recognised) |document|
        try std.testing.expectEqual(@as(u16, 503), dispatchGraphql(document, &response).status);
}

test "GraphQL ambiguous malformed or mismatched selection stays a bad request" {
    var response: [256]u8 = undefined;
    const unsupported = [_][]const u8{
        "ssg_build",
        "{ ssg_build unknown }",
        "query One { ssg_build } query Two { ssg_clean }",
        "{ ssg_build(note: \"unterminated) }",
        "{ ssg_build(options: [1, 2}) }",
        "{ ssg_build } trailing",
        "{\"query\":\"query Build { ssg_build }\",\"operationName\":\"Other\"}",
        "{\"query\":\"{ ssg_build }\",\"operationName\":\"Build\"}",
        "{\"query\":\"{ ssg_build }\",\"operationName\":\"\"}",
        "{\"query\":false,\"operationName\":\"ssg_build\"}",
    };
    for (unsupported) |document|
        try std.testing.expectEqual(@as(u16, 400), dispatchGraphql(document, &response).status);
}

// ── Wire I/O (Zig 0.16 `std.Io.net`) ────────────────────────────────────
//
// Zig 0.16 removed `std.net`; the sockets API moved onto the `std.Io`
// interface, so every call now takes an `io` handle. The process-wide Io comes from the shared
// ADR-0006 shim, re-exported by the FFI module, so the adapter and the
// cartridge behind it use ONE runtime rather than two.

const AdapterProto = enum { rest, grpc, graphql };

const CONN_BUF_LEN: usize = 16 * 1024;
const HDR_BUF_LEN: usize = 1024;

/// Handle one request using the selected protocol and close the stream.
/// Read and write errors end the connection without being returned.
fn handleConnection(io: std.Io, stream: std.Io.net.Stream, proto: AdapterProto) void {
    defer stream.close(io);

    var in_buf: [CONN_BUF_LEN]u8 = undefined;
    var stream_reader = stream.reader(io, &in_buf);
    stream_reader.interface.fillMore() catch return;
    const req = stream_reader.interface.buffered();

    var path: []const u8 = "/";
    var body: []const u8 = "";
    if (req.len > 4) {
        const line_end = std.mem.indexOf(u8, req, "\r\n") orelse req.len;
        const first_line = req[0..line_end];
        const sp1 = std.mem.indexOfScalar(u8, first_line, ' ') orelse 0;
        const rest_of = first_line[sp1 + 1 ..];
        const sp2 = std.mem.indexOfScalar(u8, rest_of, ' ') orelse rest_of.len;
        path = rest_of[0..sp2];
        const body_sep = std.mem.indexOf(u8, req, "\r\n\r\n") orelse req.len;
        body = req[@min(body_sep + 4, req.len)..];
    }

    var resp_buf: [CONN_BUF_LEN]u8 = undefined;
    const result = switch (proto) {
        .rest => dispatchRest(path, body, &resp_buf),
        .grpc => dispatchGrpc(path, body, &resp_buf),
        .graphql => dispatchGraphql(body, &resp_buf),
    };

    const ct: []const u8 = if (proto == .grpc) "application/grpc+json" else "application/json";
    var hdr_buf: [HDR_BUF_LEN]u8 = undefined;
    var stream_writer = stream.writer(io, &hdr_buf);
    const w = &stream_writer.interface;
    const reason = if (result.status == 503) "Service Unavailable" else "Error";
    w.print(
        "HTTP/1.1 {d} {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
        .{ result.status, reason, ct, result.body.len },
    ) catch return;
    w.writeAll(result.body) catch return;
    w.flush() catch return;
}

// Loopback-only by construction: cartridge adapters are internal and sit
// behind the http-capability-gateway (ADR-0004). Never bind a routable
// interface.
fn listenLoop(io: std.Io, port: u16, proto: AdapterProto) void {
    const addr: std.Io.net.IpAddress = .{ .ip4 = .{ .bytes = .{ 127, 0, 0, 1 }, .port = port } };
    var server = addr.listen(io, .{ .reuse_address = true }) catch return;
    defer server.deinit(io);
    while (true) {
        const stream = server.accept(io) catch continue;
        handleConnection(io, stream, proto);
    }
}

pub fn main() !void {
    _ = ffi.boj_cartridge_init();
    defer ffi.boj_cartridge_deinit();

    // One process-wide runtime, shared with the cartridge behind the ABI.
    const io = ffi.shim.io();

    const t1 = try std.Thread.spawn(.{}, listenLoop, .{ io, REST_PORT, AdapterProto.rest });
    const t2 = try std.Thread.spawn(.{}, listenLoop, .{ io, GRPC_PORT, AdapterProto.grpc });
    const t3 = try std.Thread.spawn(.{}, listenLoop, .{ io, GQL_PORT, AdapterProto.graphql });
    t1.join();
    t2.join();
    t3.join();
}
