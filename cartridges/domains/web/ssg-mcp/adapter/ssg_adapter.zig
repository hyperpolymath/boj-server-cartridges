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

fn dispatchGraphql(body: []const u8, resp: []u8) Response {
    if (std.mem.indexOf(u8, body, "ssg_load_content") != null)
        return dispatch("ssg_load_content", body, resp);
    if (std.mem.indexOf(u8, body, "ssg_build") != null)
        return dispatch("ssg_build", body, resp);
    if (std.mem.indexOf(u8, body, "ssg_preview") != null)
        return dispatch("ssg_preview", body, resp);
    if (std.mem.indexOf(u8, body, "ssg_deploy") != null)
        return dispatch("ssg_deploy", body, resp);
    if (std.mem.indexOf(u8, body, "ssg_clean") != null)
        return dispatch("ssg_clean", body, resp);
    return .{ .status = 400, .body = errJson(resp, "unrecognised GraphQL operation") };
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

        const graphql = dispatchGraphql(tool, &response);
        try std.testing.expectEqual(@as(u16, 503), graphql.status);
    }
}

test "unknown operations remain distinct from an unavailable backend" {
    var response: [256]u8 = undefined;
    try std.testing.expectEqual(@as(u16, 404), dispatchRest("/tools/unknown", "{}", &response).status);
    try std.testing.expectEqual(@as(u16, 404), dispatchGrpc("/Ssg/unknown", "{}", &response).status);
    try std.testing.expectEqual(@as(u16, 400), dispatchGraphql("unknown", &response).status);
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
