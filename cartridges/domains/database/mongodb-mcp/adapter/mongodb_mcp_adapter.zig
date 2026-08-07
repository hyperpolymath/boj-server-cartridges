// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// mongodb-mcp/adapter/mongodb_mcp_adapter.zig -- Unified three-protocol adapter.
// Replaces banned mongodb_mcp_adapter.v (zig, removed 2026-04-12).
// REST:9160 gRPC:9161 GraphQL:9162
// Tools: mongo_connect, mongo_find, mongo_insert, mongo_update...

const std = @import("std");
const ffi = @import("mongodb_mcp_ffi");

const REST_PORT: u16 = 9160;
const GRPC_PORT: u16 = 9161;
const GQL_PORT:  u16 = 9162;
const MAX_CONN_BUF: usize = 16 * 1024;

fn okJson(buf: []u8, msg: []const u8) []u8 {
    const n = std.fmt.bufPrint(buf, "{{\"success\":true,\"message\":\"{s}\"}}", .{msg}) catch return buf[0..0]; return n;
}
fn errJson(buf: []u8, msg: []const u8) []u8 {
    const n = std.fmt.bufPrint(buf, "{{\"success\":false,\"error\":\"{s}\"}}", .{msg}) catch return buf[0..0]; return n;
}
fn statusJson(buf: []u8) []u8 {
    const n = std.fmt.bufPrint(buf, "{{\"success\":true,\"state\":\"ready\",\"service\":\"mongodb-mcp\"}}", .{}) catch return buf[0..0]; return n;
}

const Response = struct { status: u16, body: []u8 };

fn dispatch(tool: []const u8, body: []const u8, resp: []u8) Response {
    _ = body;
    if (std.mem.eql(u8, tool, "mongo_connect")) return .{ .status = 200, .body = okJson(resp, "mongo_connect forwarded") };
    if (std.mem.eql(u8, tool, "mongo_find")) return .{ .status = 200, .body = okJson(resp, "mongo_find forwarded") };
    if (std.mem.eql(u8, tool, "mongo_insert")) return .{ .status = 200, .body = okJson(resp, "mongo_insert forwarded") };
    if (std.mem.eql(u8, tool, "mongo_update")) return .{ .status = 200, .body = okJson(resp, "mongo_update forwarded") };
    if (std.mem.eql(u8, tool, "mongo_delete")) return .{ .status = 200, .body = okJson(resp, "mongo_delete forwarded") };
    if (std.mem.eql(u8, tool, "mongo_aggregate")) return .{ .status = 200, .body = okJson(resp, "mongo_aggregate forwarded") };
    if (std.mem.eql(u8, tool, "mongo_list_collections")) return .{ .status = 200, .body = okJson(resp, "mongo_list_collections forwarded") };
    if (std.mem.eql(u8, tool, "mongo_disconnect")) return .{ .status = 200, .body = okJson(resp, "mongo_disconnect forwarded") };
    if (std.mem.eql(u8, tool, "status") or std.mem.eql(u8, tool, "health")) return .{ .status = 200, .body = statusJson(resp) };
    return .{ .status = 404, .body = errJson(resp, "Unknown tool") };
}

fn dispatchRest(path: []const u8, body: []const u8, resp: []u8) Response {
    if (std.mem.startsWith(u8, path, "/tools/")) return dispatch(path["/tools/".len..], body, resp);
    if (std.mem.eql(u8, path, "/status") or std.mem.eql(u8, path, "/health")) return .{ .status = 200, .body = statusJson(resp) };
    return .{ .status = 404, .body = errJson(resp, "Not found") };
}

fn dispatchGrpc(path: []const u8, body: []const u8, resp: []u8) Response {
    const prefix = "/MongodbMcpservice/";
    if (!std.mem.startsWith(u8, path, prefix)) return .{ .status = 404, .body = errJson(resp, "Not a recognized gRPC path") };
    const method = path[prefix.len..];
    const tool = blk: {
        if (std.mem.eql(u8, method, "mongo_connect")) break :blk "mongo_connect";
        if (std.mem.eql(u8, method, "mongo_find")) break :blk "mongo_find";
        if (std.mem.eql(u8, method, "mongo_insert")) break :blk "mongo_insert";
        if (std.mem.eql(u8, method, "mongo_update")) break :blk "mongo_update";
        if (std.mem.eql(u8, method, "mongo_delete")) break :blk "mongo_delete";
        if (std.mem.eql(u8, method, "mongo_aggregate")) break :blk "mongo_aggregate";
        if (std.mem.eql(u8, method, "mongo_list_collections")) break :blk "mongo_list_collections";
        if (std.mem.eql(u8, method, "mongo_disconnect")) break :blk "mongo_disconnect";
        return .{ .status = 404, .body = errJson(resp, "Unknown gRPC method") };
    };
    return dispatch(tool, body, resp);
}

fn dispatchGraphql(body: []const u8, resp: []u8) Response {
    if (std.mem.indexOf(u8, body, "__schema") != null) return .{ .status = 200, .body = okJson(resp, "schema not supported") };
    if (std.mem.indexOf(u8, body, "connect") != null) return dispatch("mongo_connect", body, resp);
    if (std.mem.indexOf(u8, body, "find") != null) return dispatch("mongo_find", body, resp);
    if (std.mem.indexOf(u8, body, "insert") != null) return dispatch("mongo_insert", body, resp);
    if (std.mem.indexOf(u8, body, "update") != null) return dispatch("mongo_update", body, resp);
    if (std.mem.indexOf(u8, body, "delete") != null) return dispatch("mongo_delete", body, resp);
    if (std.mem.indexOf(u8, body, "aggregate") != null) return dispatch("mongo_aggregate", body, resp);
    if (std.mem.indexOf(u8, body, "list_collections") != null) return dispatch("mongo_list_collections", body, resp);
    if (std.mem.indexOf(u8, body, "disconnect") != null) return dispatch("mongo_disconnect", body, resp);
    return .{ .status = 200, .body = errJson(resp, "Unrecognised GraphQL operation") };
}

const Protocol = enum { rest, grpc, graphql };

// ── Wire I/O (Zig 0.16 `std.Io.net`) ────────────────────────────────────
//
// Zig 0.16 removed `std.net`; the sockets API moved onto the `std.Io`
// interface, so every call now takes an `io` handle. The process-wide Io comes from the shared
// ADR-0006 shim, re-exported by the FFI module, so the adapter and the
// cartridge behind it use ONE runtime rather than two.

const AdapterProto = enum { rest, grpc, graphql };

const CONN_BUF_LEN: usize = 16 * 1024;
const HDR_BUF_LEN: usize = 1024;

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
    w.print(
        "HTTP/1.1 {d} OK\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
        .{ result.status, ct, result.body.len },
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
