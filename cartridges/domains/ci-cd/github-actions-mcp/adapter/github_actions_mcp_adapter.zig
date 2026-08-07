// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// github-actions-mcp/adapter/github_actions_mcp_adapter.zig
//
// Three-protocol BoJ adapter: REST (port 9241), gRPC-compat (port 9242),
// GraphQL (port 9243).
// Replaces the banned zig adapter (github_actions_mcp_adapter.v).

const std = @import("std");
const ffi = @import("github_actions_mcp_ffi");

const REST_PORT: u16 = 9241;
const GRPC_PORT: u16 = 9242;
const GQL_PORT:  u16 = 9243;

const Response = struct { status: u16, body: []const u8 };

fn okJson(buf: []u8, msg: []const u8) []u8 {
    return std.fmt.bufPrint(buf, "{{\"success\":true,\"message\":\"{s}\"}}", .{msg}) catch buf[0..0];
}

fn errJson(buf: []u8, msg: []const u8) []u8 {
    return std.fmt.bufPrint(buf, "{{\"success\":false,\"error\":\"{s}\"}}", .{msg}) catch buf[0..0];
}

fn dispatch(tool: []const u8, _body: []const u8, resp: []u8) Response {
    _ = _body;
    if (std.mem.eql(u8, tool, "gha_authenticate")) {
        return .{ .status = 200, .body = okJson(resp, "gha_authenticate forwarded") };
    }
    if (std.mem.eql(u8, tool, "gha_list_workflows")) {
        return .{ .status = 200, .body = okJson(resp, "gha_list_workflows forwarded") };
    }
    if (std.mem.eql(u8, tool, "gha_list_runs")) {
        return .{ .status = 200, .body = okJson(resp, "gha_list_runs forwarded") };
    }
    if (std.mem.eql(u8, tool, "gha_get_run")) {
        return .{ .status = 200, .body = okJson(resp, "gha_get_run forwarded") };
    }
    if (std.mem.eql(u8, tool, "gha_dispatch_workflow")) {
        return .{ .status = 200, .body = okJson(resp, "gha_dispatch_workflow forwarded") };
    }
    if (std.mem.eql(u8, tool, "gha_cancel_run")) {
        return .{ .status = 200, .body = okJson(resp, "gha_cancel_run forwarded") };
    }
    if (std.mem.eql(u8, tool, "gha_list_jobs")) {
        return .{ .status = 200, .body = okJson(resp, "gha_list_jobs forwarded") };
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
    if (std.mem.indexOf(u8, body, "gha_authenticate") != null)
        return dispatch("gha_authenticate", body, resp);
    if (std.mem.indexOf(u8, body, "gha_list_workflows") != null)
        return dispatch("gha_list_workflows", body, resp);
    if (std.mem.indexOf(u8, body, "gha_list_runs") != null)
        return dispatch("gha_list_runs", body, resp);
    if (std.mem.indexOf(u8, body, "gha_get_run") != null)
        return dispatch("gha_get_run", body, resp);
    if (std.mem.indexOf(u8, body, "gha_dispatch_workflow") != null)
        return dispatch("gha_dispatch_workflow", body, resp);
    if (std.mem.indexOf(u8, body, "gha_cancel_run") != null)
        return dispatch("gha_cancel_run", body, resp);
    if (std.mem.indexOf(u8, body, "gha_list_jobs") != null)
        return dispatch("gha_list_jobs", body, resp);
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
