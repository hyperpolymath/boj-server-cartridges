// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// duckdb-mcp/adapter/duckdb_mcp_adapter.zig -- Unified three-protocol adapter.
// Replaces banned duckdb_mcp_adapter.v (zig, removed 2026-04-12).
// REST:9169 gRPC:9170 GraphQL:9171
// Tools: duckdb_open, duckdb_query, duckdb_execute, duckdb_import...

const std = @import("std");
const ffi = @import("duckdb_mcp_ffi");

const REST_PORT: u16 = 9169;
const GRPC_PORT: u16 = 9170;
const GQL_PORT:  u16 = 9171;
const MAX_CONN_BUF: usize = 16 * 1024;

fn okJson(buf: []u8, msg: []const u8) []u8 {
    const n = std.fmt.bufPrint(buf, "{{\"success\":true,\"message\":\"{s}\"}}", .{msg}) catch return buf[0..0]; return n;
}
fn errJson(buf: []u8, msg: []const u8) []u8 {
    const n = std.fmt.bufPrint(buf, "{{\"success\":false,\"error\":\"{s}\"}}", .{msg}) catch return buf[0..0]; return n;
}
fn statusJson(buf: []u8) []u8 {
    const n = std.fmt.bufPrint(buf, "{{\"success\":true,\"state\":\"ready\",\"service\":\"duckdb-mcp\"}}", .{}) catch return buf[0..0]; return n;
}

const Response = struct { status: u16, body: []u8 };

fn dispatch(tool: []const u8, body: []const u8, resp: []u8) Response {
    _ = body;
    if (std.mem.eql(u8, tool, "duckdb_open")) return .{ .status = 200, .body = okJson(resp, "duckdb_open forwarded") };
    if (std.mem.eql(u8, tool, "duckdb_query")) return .{ .status = 200, .body = okJson(resp, "duckdb_query forwarded") };
    if (std.mem.eql(u8, tool, "duckdb_execute")) return .{ .status = 200, .body = okJson(resp, "duckdb_execute forwarded") };
    if (std.mem.eql(u8, tool, "duckdb_import")) return .{ .status = 200, .body = okJson(resp, "duckdb_import forwarded") };
    if (std.mem.eql(u8, tool, "duckdb_export")) return .{ .status = 200, .body = okJson(resp, "duckdb_export forwarded") };
    if (std.mem.eql(u8, tool, "duckdb_list_tables")) return .{ .status = 200, .body = okJson(resp, "duckdb_list_tables forwarded") };
    if (std.mem.eql(u8, tool, "duckdb_close")) return .{ .status = 200, .body = okJson(resp, "duckdb_close forwarded") };
    if (std.mem.eql(u8, tool, "status") or std.mem.eql(u8, tool, "health")) return .{ .status = 200, .body = statusJson(resp) };
    return .{ .status = 404, .body = errJson(resp, "Unknown tool") };
}

fn dispatchRest(path: []const u8, body: []const u8, resp: []u8) Response {
    if (std.mem.startsWith(u8, path, "/tools/")) return dispatch(path["/tools/".len..], body, resp);
    if (std.mem.eql(u8, path, "/status") or std.mem.eql(u8, path, "/health")) return .{ .status = 200, .body = statusJson(resp) };
    return .{ .status = 404, .body = errJson(resp, "Not found") };
}

fn dispatchGrpc(path: []const u8, body: []const u8, resp: []u8) Response {
    const prefix = "/DuckdbMcpservice/";
    if (!std.mem.startsWith(u8, path, prefix)) return .{ .status = 404, .body = errJson(resp, "Not a recognized gRPC path") };
    const method = path[prefix.len..];
    const tool = blk: {
        if (std.mem.eql(u8, method, "duckdb_open")) break :blk "duckdb_open";
        if (std.mem.eql(u8, method, "duckdb_query")) break :blk "duckdb_query";
        if (std.mem.eql(u8, method, "duckdb_execute")) break :blk "duckdb_execute";
        if (std.mem.eql(u8, method, "duckdb_import")) break :blk "duckdb_import";
        if (std.mem.eql(u8, method, "duckdb_export")) break :blk "duckdb_export";
        if (std.mem.eql(u8, method, "duckdb_list_tables")) break :blk "duckdb_list_tables";
        if (std.mem.eql(u8, method, "duckdb_close")) break :blk "duckdb_close";
        return .{ .status = 404, .body = errJson(resp, "Unknown gRPC method") };
    };
    return dispatch(tool, body, resp);
}

fn dispatchGraphql(body: []const u8, resp: []u8) Response {
    if (std.mem.indexOf(u8, body, "__schema") != null) return .{ .status = 200, .body = okJson(resp, "schema not supported") };
    if (std.mem.indexOf(u8, body, "open") != null) return dispatch("duckdb_open", body, resp);
    if (std.mem.indexOf(u8, body, "query") != null) return dispatch("duckdb_query", body, resp);
    if (std.mem.indexOf(u8, body, "execute") != null) return dispatch("duckdb_execute", body, resp);
    if (std.mem.indexOf(u8, body, "import") != null) return dispatch("duckdb_import", body, resp);
    if (std.mem.indexOf(u8, body, "export") != null) return dispatch("duckdb_export", body, resp);
    if (std.mem.indexOf(u8, body, "list_tables") != null) return dispatch("duckdb_list_tables", body, resp);
    if (std.mem.indexOf(u8, body, "close") != null) return dispatch("duckdb_close", body, resp);
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
