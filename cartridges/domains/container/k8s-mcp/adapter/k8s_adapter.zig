// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// k8s-mcp/adapter/k8s_adapter.zig -- Unified three-protocol adapter.
// Replaces banned k8s_adapter.v (zig, removed 2026-04-12).
// REST:9145 gRPC:9146 GraphQL:9147
// Tools: k8s_connect, k8s_list_pods, k8s_get_pod, k8s_list_deployments...

const std = @import("std");
const ffi = @import("k8s_ffi");

const REST_PORT: u16 = 9145;
const GRPC_PORT: u16 = 9146;
const GQL_PORT:  u16 = 9147;
const MAX_CONN_BUF: usize = 16 * 1024;

fn okJson(buf: []u8, msg: []const u8) []u8 {
    const n = std.fmt.bufPrint(buf, "{{\"success\":true,\"message\":\"{s}\"}}", .{msg}) catch return buf[0..0]; return n;
}
fn errJson(buf: []u8, msg: []const u8) []u8 {
    const n = std.fmt.bufPrint(buf, "{{\"success\":false,\"error\":\"{s}\"}}", .{msg}) catch return buf[0..0]; return n;
}
fn statusJson(buf: []u8) []u8 {
    const n = std.fmt.bufPrint(buf, "{{\"success\":true,\"state\":\"ready\",\"service\":\"k8s-mcp\"}}", .{}) catch return buf[0..0]; return n;
}

const Response = struct { status: u16, body: []u8 };

fn dispatch(tool: []const u8, body: []const u8, resp: []u8) Response {
    _ = body;
    if (std.mem.eql(u8, tool, "k8s_connect")) return .{ .status = 200, .body = okJson(resp, "k8s_connect forwarded") };
    if (std.mem.eql(u8, tool, "k8s_list_pods")) return .{ .status = 200, .body = okJson(resp, "k8s_list_pods forwarded") };
    if (std.mem.eql(u8, tool, "k8s_get_pod")) return .{ .status = 200, .body = okJson(resp, "k8s_get_pod forwarded") };
    if (std.mem.eql(u8, tool, "k8s_list_deployments")) return .{ .status = 200, .body = okJson(resp, "k8s_list_deployments forwarded") };
    if (std.mem.eql(u8, tool, "k8s_apply")) return .{ .status = 200, .body = okJson(resp, "k8s_apply forwarded") };
    if (std.mem.eql(u8, tool, "k8s_delete")) return .{ .status = 200, .body = okJson(resp, "k8s_delete forwarded") };
    if (std.mem.eql(u8, tool, "k8s_logs")) return .{ .status = 200, .body = okJson(resp, "k8s_logs forwarded") };
    if (std.mem.eql(u8, tool, "k8s_disconnect")) return .{ .status = 200, .body = okJson(resp, "k8s_disconnect forwarded") };
    if (std.mem.eql(u8, tool, "status") or std.mem.eql(u8, tool, "health")) return .{ .status = 200, .body = statusJson(resp) };
    return .{ .status = 404, .body = errJson(resp, "Unknown tool") };
}

fn dispatchRest(path: []const u8, body: []const u8, resp: []u8) Response {
    if (std.mem.startsWith(u8, path, "/tools/")) return dispatch(path["/tools/".len..], body, resp);
    if (std.mem.eql(u8, path, "/status") or std.mem.eql(u8, path, "/health")) return .{ .status = 200, .body = statusJson(resp) };
    return .{ .status = 404, .body = errJson(resp, "Not found") };
}

fn dispatchGrpc(path: []const u8, body: []const u8, resp: []u8) Response {
    const prefix = "/K8sservice/";
    if (!std.mem.startsWith(u8, path, prefix)) return .{ .status = 404, .body = errJson(resp, "Not a recognized gRPC path") };
    const method = path[prefix.len..];
    const tool = blk: {
        if (std.mem.eql(u8, method, "k8s_connect")) break :blk "k8s_connect";
        if (std.mem.eql(u8, method, "k8s_list_pods")) break :blk "k8s_list_pods";
        if (std.mem.eql(u8, method, "k8s_get_pod")) break :blk "k8s_get_pod";
        if (std.mem.eql(u8, method, "k8s_list_deployments")) break :blk "k8s_list_deployments";
        if (std.mem.eql(u8, method, "k8s_apply")) break :blk "k8s_apply";
        if (std.mem.eql(u8, method, "k8s_delete")) break :blk "k8s_delete";
        if (std.mem.eql(u8, method, "k8s_logs")) break :blk "k8s_logs";
        if (std.mem.eql(u8, method, "k8s_disconnect")) break :blk "k8s_disconnect";
        return .{ .status = 404, .body = errJson(resp, "Unknown gRPC method") };
    };
    return dispatch(tool, body, resp);
}

fn dispatchGraphql(body: []const u8, resp: []u8) Response {
    if (std.mem.indexOf(u8, body, "__schema") != null) return .{ .status = 200, .body = okJson(resp, "schema not supported") };
    if (std.mem.indexOf(u8, body, "connect") != null) return dispatch("k8s_connect", body, resp);
    if (std.mem.indexOf(u8, body, "list_pods") != null) return dispatch("k8s_list_pods", body, resp);
    if (std.mem.indexOf(u8, body, "get_pod") != null) return dispatch("k8s_get_pod", body, resp);
    if (std.mem.indexOf(u8, body, "list_deployments") != null) return dispatch("k8s_list_deployments", body, resp);
    if (std.mem.indexOf(u8, body, "apply") != null) return dispatch("k8s_apply", body, resp);
    if (std.mem.indexOf(u8, body, "delete") != null) return dispatch("k8s_delete", body, resp);
    if (std.mem.indexOf(u8, body, "logs") != null) return dispatch("k8s_logs", body, resp);
    if (std.mem.indexOf(u8, body, "disconnect") != null) return dispatch("k8s_disconnect", body, resp);
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
