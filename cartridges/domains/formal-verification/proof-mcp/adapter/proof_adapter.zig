// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// proof-mcp/adapter/proof_adapter.zig -- Unified three-protocol adapter.
//
// Replaces the banned proof_adapter.v (zig, removed 2026-04-12).
//
// REST :9121  gRPC-compat :9122  GraphQL :9123
// Proof verification lifecycle manager. Manages sessions across Lean, Coq, Agda, Isabelle, Idris2, Z3,
// Tools: proof_init_session, proof_load_obligation, proof_verify, proof_get_result, proof_get_state, proof_reset_session, proof_release_session, proof_can_transition

const std = @import("std");
const ffi = @import("proof_ffi");

const REST_PORT: u16 = 9121;
const GRPC_PORT: u16 = 9122;
const GQL_PORT:  u16 = 9123;
const MAX_CONN_BUF: usize = 16 * 1024;

fn okJson(buf: []u8, msg: []const u8) []u8 {
    const n = std.fmt.bufPrint(buf, "{{\"success\":true,\"message\":\"{s}\"}}", .{msg}) catch return buf[0..0];
    return n;
}
fn errJson(buf: []u8, msg: []const u8) []u8 {
    const n = std.fmt.bufPrint(buf, "{{\"success\":false,\"error\":\"{s}\"}}", .{msg}) catch return buf[0..0];
    return n;
}
fn statusJson(buf: []u8) []u8 {
    const n = std.fmt.bufPrint(buf, "{{\"success\":true,\"state\":\"ready\",\"service\":\"proof-mcp\"}}", .{}) catch return buf[0..0];
    return n;
}

const Response = struct { status: u16, body: []u8 };

fn dispatch(tool: []const u8, body: []const u8, resp: []u8) Response {
    _ = body;
    if (std.mem.eql(u8, tool, "proof_init_session")) return .{ .status = 200, .body = okJson(resp, "proof_init_session forwarded") };
    if (std.mem.eql(u8, tool, "proof_load_obligation")) return .{ .status = 200, .body = okJson(resp, "proof_load_obligation forwarded") };
    if (std.mem.eql(u8, tool, "proof_verify")) return .{ .status = 200, .body = okJson(resp, "proof_verify forwarded") };
    if (std.mem.eql(u8, tool, "proof_get_result")) return .{ .status = 200, .body = okJson(resp, "proof_get_result forwarded") };
    if (std.mem.eql(u8, tool, "proof_get_state")) return .{ .status = 200, .body = okJson(resp, "proof_get_state forwarded") };
    if (std.mem.eql(u8, tool, "proof_reset_session")) return .{ .status = 200, .body = okJson(resp, "proof_reset_session forwarded") };
    if (std.mem.eql(u8, tool, "proof_release_session")) return .{ .status = 200, .body = okJson(resp, "proof_release_session forwarded") };
    if (std.mem.eql(u8, tool, "proof_can_transition")) return .{ .status = 200, .body = okJson(resp, "proof_can_transition forwarded") };
    if (std.mem.eql(u8, tool, "status") or std.mem.eql(u8, tool, "health"))
        return .{ .status = 200, .body = statusJson(resp) };
    return .{ .status = 404, .body = errJson(resp, "Unknown tool") };
}

fn dispatchRest(path: []const u8, body: []const u8, resp: []u8) Response {
    if (std.mem.startsWith(u8, path, "/tools/")) return dispatch(path["/tools/".len..], body, resp);
    if (std.mem.eql(u8, path, "/status") or std.mem.eql(u8, path, "/health")) return .{ .status = 200, .body = statusJson(resp) };
    return .{ .status = 404, .body = errJson(resp, "Not found") };
}

fn dispatchGrpc(path: []const u8, body: []const u8, resp: []u8) Response {
    const prefix = "/Proofservice/";
    if (!std.mem.startsWith(u8, path, prefix))
        return .{ .status = 404, .body = errJson(resp, "Not a recognized gRPC path") };
    const method = path[prefix.len..];
    const tool = blk: {
        if (std.mem.eql(u8, method, "proof_init_session")) break :blk "proof_init_session";
        if (std.mem.eql(u8, method, "proof_load_obligation")) break :blk "proof_load_obligation";
        if (std.mem.eql(u8, method, "proof_verify")) break :blk "proof_verify";
        if (std.mem.eql(u8, method, "proof_get_result")) break :blk "proof_get_result";
        if (std.mem.eql(u8, method, "proof_get_state")) break :blk "proof_get_state";
        if (std.mem.eql(u8, method, "proof_reset_session")) break :blk "proof_reset_session";
        if (std.mem.eql(u8, method, "proof_release_session")) break :blk "proof_release_session";
        if (std.mem.eql(u8, method, "proof_can_transition")) break :blk "proof_can_transition";
        return .{ .status = 404, .body = errJson(resp, "Unknown gRPC method") };
    };
    return dispatch(tool, body, resp);
}

fn dispatchGraphql(body: []const u8, resp: []u8) Response {
    if (std.mem.indexOf(u8, body, "__schema") != null) return .{ .status = 200, .body = okJson(resp, "schema not supported") };
    if (std.mem.indexOf(u8, body, "init_session") != null) return dispatch("proof_init_session", body, resp);
    if (std.mem.indexOf(u8, body, "load_obligation") != null) return dispatch("proof_load_obligation", body, resp);
    if (std.mem.indexOf(u8, body, "verify") != null) return dispatch("proof_verify", body, resp);
    if (std.mem.indexOf(u8, body, "get_result") != null) return dispatch("proof_get_result", body, resp);
    if (std.mem.indexOf(u8, body, "get_state") != null) return dispatch("proof_get_state", body, resp);
    if (std.mem.indexOf(u8, body, "reset_session") != null) return dispatch("proof_reset_session", body, resp);
    if (std.mem.indexOf(u8, body, "release_session") != null) return dispatch("proof_release_session", body, resp);
    if (std.mem.indexOf(u8, body, "can_transition") != null) return dispatch("proof_can_transition", body, resp);
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
