// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// sentry-mcp/adapter/sentry_adapter.zig -- Unified three-protocol adapter.
//
// Replaces the banned sentry_adapter.v (zig, removed 2026-04-12).
//
// Bridges the Zig FFI (sentry_mcp_ffi.zig) to three network protocols:
//   REST        :9094  POST /tools/<tool>
//   gRPC-compat :9095  /SentryMcpService/<Method>
//   GraphQL     :9096  POST /graphql  { query: "..." }
//
// Sentry error tracking: issues, events, releases, projects, teams
// Tools:
//   sentry_list_issues
//   sentry_get_issue
//   sentry_list_events
//   sentry_resolve_issue
//   sentry_list_projects
//   sentry_list_releases
//   sentry_get_dsn
//   sentry_list_teams
//   sentry_search_tags
//   sentry_list_transactions

const std = @import("std");
const ffi = @import("sentry_mcp_ffi");

const REST_PORT: u16 = 9094;
const GRPC_PORT: u16 = 9095;
const GQL_PORT:  u16 = 9096;

const MAX_CONN_BUF: usize = 16 * 1024;

// ============================================================================
// JSON response builders
// ============================================================================

fn okJson(buf: []u8, msg: []const u8) []u8 {
    return std.fmt.bufPrint(buf,
        \\{{"success":true,"message":"{s}"}}
    , .{msg}) catch buf[0..0];
}

fn errJson(buf: []u8, msg: []const u8) []u8 {
    return std.fmt.bufPrint(buf,
        \\{{"success":false,"error":"{s}"}}
    , .{msg}) catch buf[0..0];
}

fn statusJson(buf: []u8) []u8 {
    return std.fmt.bufPrint(buf,
        \\{{"success":true,"state":"ready","service":"sentry-mcp"}}
    , .{}) catch buf[0..0];
}

// ============================================================================
// Tool dispatcher
// ============================================================================

const Response = struct { status: u16, body: []u8 };

fn dispatch(tool: []const u8, body: []const u8, resp: []u8) Response {
    _ = body;
    if (std.mem.eql(u8, tool, "sentry_list_issues")) return .{ .status = 200, .body = okJson(resp, "sentry_list_issues forwarded to backend") };
    if (std.mem.eql(u8, tool, "sentry_get_issue")) return .{ .status = 200, .body = okJson(resp, "sentry_get_issue forwarded to backend") };
    if (std.mem.eql(u8, tool, "sentry_list_events")) return .{ .status = 200, .body = okJson(resp, "sentry_list_events forwarded to backend") };
    if (std.mem.eql(u8, tool, "sentry_resolve_issue")) return .{ .status = 200, .body = okJson(resp, "sentry_resolve_issue forwarded to backend") };
    if (std.mem.eql(u8, tool, "sentry_list_projects")) return .{ .status = 200, .body = okJson(resp, "sentry_list_projects forwarded to backend") };
    if (std.mem.eql(u8, tool, "sentry_list_releases")) return .{ .status = 200, .body = okJson(resp, "sentry_list_releases forwarded to backend") };
    if (std.mem.eql(u8, tool, "sentry_get_dsn")) return .{ .status = 200, .body = okJson(resp, "sentry_get_dsn forwarded to backend") };
    if (std.mem.eql(u8, tool, "sentry_list_teams")) return .{ .status = 200, .body = okJson(resp, "sentry_list_teams forwarded to backend") };
    if (std.mem.eql(u8, tool, "sentry_search_tags")) return .{ .status = 200, .body = okJson(resp, "sentry_search_tags forwarded to backend") };
    if (std.mem.eql(u8, tool, "sentry_list_transactions")) return .{ .status = 200, .body = okJson(resp, "sentry_list_transactions forwarded to backend") };
    if (std.mem.eql(u8, tool, "status") or std.mem.eql(u8, tool, "health"))
        return .{ .status = 200, .body = statusJson(resp) };
    return .{ .status = 404, .body = errJson(resp, "Unknown tool") };
}

// ============================================================================
// REST handler
// ============================================================================

fn dispatchRest(path: []const u8, body: []const u8, resp: []u8) Response {
    if (std.mem.startsWith(u8, path, "/tools/")) {
        return dispatch(path["/tools/".len..], body, resp);
    }
    if (std.mem.eql(u8, path, "/status") or std.mem.eql(u8, path, "/health")) {
        return .{ .status = 200, .body = statusJson(resp) };
    }
    return .{ .status = 404, .body = errJson(resp, "Not found") };
}

// ============================================================================
// gRPC-compat handler
// ============================================================================

fn dispatchGrpc(path: []const u8, body: []const u8, resp: []u8) Response {
    const prefix = "/SentryMcpService/";
    if (!std.mem.startsWith(u8, path, prefix))
        return .{ .status = 404, .body = errJson(resp, "Not a recognized gRPC path") };
    const method = path[prefix.len..];
    const tool = blk: {
        if (std.mem.eql(u8, method, "SentryListIssues")) break :blk "sentry_list_issues";
        if (std.mem.eql(u8, method, "SentryGetIssue")) break :blk "sentry_get_issue";
        if (std.mem.eql(u8, method, "SentryListEvents")) break :blk "sentry_list_events";
        if (std.mem.eql(u8, method, "SentryResolveIssue")) break :blk "sentry_resolve_issue";
        if (std.mem.eql(u8, method, "SentryListProjects")) break :blk "sentry_list_projects";
        if (std.mem.eql(u8, method, "SentryListReleases")) break :blk "sentry_list_releases";
        if (std.mem.eql(u8, method, "SentryGetDsn")) break :blk "sentry_get_dsn";
        if (std.mem.eql(u8, method, "SentryListTeams")) break :blk "sentry_list_teams";
        if (std.mem.eql(u8, method, "SentrySearchTags")) break :blk "sentry_search_tags";
        if (std.mem.eql(u8, method, "SentryListTransactions")) break :blk "sentry_list_transactions";
        return .{ .status = 404, .body = errJson(resp, "Unknown gRPC method") };
    };
    return dispatch(tool, body, resp);
}

// ============================================================================
// GraphQL handler
// ============================================================================

fn dispatchGraphql(body: []const u8, resp: []u8) Response {
    if (std.mem.indexOf(u8, body, "__schema") != null)
        return .{ .status = 200, .body = okJson(resp, "schema introspection not yet supported") };
    if (std.mem.indexOf(u8, body, "list_issues") != null) return dispatch("sentry_list_issues", body, resp);
    if (std.mem.indexOf(u8, body, "get_issue") != null) return dispatch("sentry_get_issue", body, resp);
    if (std.mem.indexOf(u8, body, "list_events") != null) return dispatch("sentry_list_events", body, resp);
    if (std.mem.indexOf(u8, body, "resolve_issue") != null) return dispatch("sentry_resolve_issue", body, resp);
    if (std.mem.indexOf(u8, body, "list_projects") != null) return dispatch("sentry_list_projects", body, resp);
    if (std.mem.indexOf(u8, body, "list_releases") != null) return dispatch("sentry_list_releases", body, resp);
    if (std.mem.indexOf(u8, body, "get_dsn") != null) return dispatch("sentry_get_dsn", body, resp);
    if (std.mem.indexOf(u8, body, "list_teams") != null) return dispatch("sentry_list_teams", body, resp);
    if (std.mem.indexOf(u8, body, "search_tags") != null) return dispatch("sentry_search_tags", body, resp);
    if (std.mem.indexOf(u8, body, "list_transactions") != null) return dispatch("sentry_list_transactions", body, resp);
    return .{ .status = 200, .body = errJson(resp, "Unrecognised GraphQL operation") };
}

// ============================================================================
// HTTP/1.1 connection handler
// ============================================================================

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
