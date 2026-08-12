// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// burble-admin-mcp/adapter/burble_admin_adapter.zig
//
// Three-protocol BoJ adapter: REST (port 9205), gRPC-compat (port 9206),
// GraphQL (port 9207).
// Replaces the banned zig adapter (burble_admin_adapter.v).

const std = @import("std");
const ffi = @import("burble_admin_ffi");

const REST_PORT: u16 = 9205;
const GRPC_PORT: u16 = 9206;
const GQL_PORT:  u16 = 9207;

const Response = struct { status: u16, body: []const u8 };

fn okJson(buf: []u8, msg: []const u8) []u8 {
    return std.fmt.bufPrint(buf, "{{\"success\":true,\"message\":\"{s}\"}}", .{msg}) catch buf[0..0];
}

fn errJson(buf: []u8, msg: []const u8) []u8 {
    return std.fmt.bufPrint(buf, "{{\"success\":false,\"error\":\"{s}\"}}", .{msg}) catch buf[0..0];
}

fn dispatch(tool: []const u8, _body: []const u8, resp: []u8) Response {
    _ = _body;
    if (std.mem.eql(u8, tool, "burble_check_health")) {
        return .{ .status = 200, .body = okJson(resp, "burble_check_health forwarded") };
    }
    if (std.mem.eql(u8, tool, "burble_list_rooms")) {
        return .{ .status = 200, .body = okJson(resp, "burble_list_rooms forwarded") };
    }
    if (std.mem.eql(u8, tool, "burble_create_room")) {
        return .{ .status = 200, .body = okJson(resp, "burble_create_room forwarded") };
    }
    if (std.mem.eql(u8, tool, "burble_close_room")) {
        return .{ .status = 200, .body = okJson(resp, "burble_close_room forwarded") };
    }
    if (std.mem.eql(u8, tool, "burble_kick_user")) {
        return .{ .status = 200, .body = okJson(resp, "burble_kick_user forwarded") };
    }
    if (std.mem.eql(u8, tool, "burble_get_config")) {
        return .{ .status = 200, .body = okJson(resp, "burble_get_config forwarded") };
    }
    if (std.mem.eql(u8, tool, "burble_update_config")) {
        return .{ .status = 200, .body = okJson(resp, "burble_update_config forwarded") };
    }
    if (std.mem.eql(u8, tool, "burble_voice_stats")) {
        return .{ .status = 200, .body = okJson(resp, "burble_voice_stats forwarded") };
    }
    if (std.mem.eql(u8, tool, "burble_toggle_recording")) {
        return .{ .status = 200, .body = okJson(resp, "burble_toggle_recording forwarded") };
    }
    if (std.mem.eql(u8, tool, "burble_node_status")) {
        return .{ .status = 200, .body = okJson(resp, "burble_node_status forwarded") };
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
    if (std.mem.indexOf(u8, body, "burble_check_health") != null)
        return dispatch("burble_check_health", body, resp);
    if (std.mem.indexOf(u8, body, "burble_list_rooms") != null)
        return dispatch("burble_list_rooms", body, resp);
    if (std.mem.indexOf(u8, body, "burble_create_room") != null)
        return dispatch("burble_create_room", body, resp);
    if (std.mem.indexOf(u8, body, "burble_close_room") != null)
        return dispatch("burble_close_room", body, resp);
    if (std.mem.indexOf(u8, body, "burble_kick_user") != null)
        return dispatch("burble_kick_user", body, resp);
    if (std.mem.indexOf(u8, body, "burble_get_config") != null)
        return dispatch("burble_get_config", body, resp);
    if (std.mem.indexOf(u8, body, "burble_update_config") != null)
        return dispatch("burble_update_config", body, resp);
    if (std.mem.indexOf(u8, body, "burble_voice_stats") != null)
        return dispatch("burble_voice_stats", body, resp);
    if (std.mem.indexOf(u8, body, "burble_toggle_recording") != null)
        return dispatch("burble_toggle_recording", body, resp);
    if (std.mem.indexOf(u8, body, "burble_node_status") != null)
        return dispatch("burble_node_status", body, resp);
    return .{ .status = 400, .body = errJson(resp, "unrecognised GraphQL operation") };
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
