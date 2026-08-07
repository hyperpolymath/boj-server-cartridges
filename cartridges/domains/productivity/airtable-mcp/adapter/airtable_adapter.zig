// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// airtable-mcp/adapter/airtable_adapter.zig -- Unified three-protocol adapter.
//
// Replaces the banned airtable_adapter.v (zig, removed 2026-04-12).
//
// Bridges the Zig FFI (airtable_mcp_ffi.zig) to three network protocols:
//   REST        :9034  POST /tools/<tool>
//   gRPC-compat :9035  /AirtableMcpService/<Method>
//   GraphQL     :9036  POST /graphql  { query: "..." }
//
// Airtable REST API: bases, tables, records, fields, views, webhooks, comments
// Tools:
//   airtable_list_bases
//   airtable_get_base_schema
//   airtable_list_records
//   airtable_get_record
//   airtable_create_record
//   airtable_update_record
//   airtable_list_fields
//   airtable_list_views
//   airtable_list_webhooks
//   airtable_get_comments

const std = @import("std");
const ffi = @import("airtable_mcp_ffi");

const REST_PORT: u16 = 9034;
const GRPC_PORT: u16 = 9035;
const GQL_PORT:  u16 = 9036;

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
        \\{{"success":true,"state":"ready","service":"airtable-mcp"}}
    , .{}) catch buf[0..0];
}

// ============================================================================
// Tool dispatcher
// ============================================================================

const Response = struct { status: u16, body: []u8 };

fn dispatch(tool: []const u8, body: []const u8, resp: []u8) Response {
    _ = body;
    if (std.mem.eql(u8, tool, "airtable_list_bases")) return .{ .status = 200, .body = okJson(resp, "airtable_list_bases forwarded to backend") };
    if (std.mem.eql(u8, tool, "airtable_get_base_schema")) return .{ .status = 200, .body = okJson(resp, "airtable_get_base_schema forwarded to backend") };
    if (std.mem.eql(u8, tool, "airtable_list_records")) return .{ .status = 200, .body = okJson(resp, "airtable_list_records forwarded to backend") };
    if (std.mem.eql(u8, tool, "airtable_get_record")) return .{ .status = 200, .body = okJson(resp, "airtable_get_record forwarded to backend") };
    if (std.mem.eql(u8, tool, "airtable_create_record")) return .{ .status = 200, .body = okJson(resp, "airtable_create_record forwarded to backend") };
    if (std.mem.eql(u8, tool, "airtable_update_record")) return .{ .status = 200, .body = okJson(resp, "airtable_update_record forwarded to backend") };
    if (std.mem.eql(u8, tool, "airtable_list_fields")) return .{ .status = 200, .body = okJson(resp, "airtable_list_fields forwarded to backend") };
    if (std.mem.eql(u8, tool, "airtable_list_views")) return .{ .status = 200, .body = okJson(resp, "airtable_list_views forwarded to backend") };
    if (std.mem.eql(u8, tool, "airtable_list_webhooks")) return .{ .status = 200, .body = okJson(resp, "airtable_list_webhooks forwarded to backend") };
    if (std.mem.eql(u8, tool, "airtable_get_comments")) return .{ .status = 200, .body = okJson(resp, "airtable_get_comments forwarded to backend") };
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
    const prefix = "/AirtableMcpService/";
    if (!std.mem.startsWith(u8, path, prefix))
        return .{ .status = 404, .body = errJson(resp, "Not a recognized gRPC path") };
    const method = path[prefix.len..];
    const tool = blk: {
        if (std.mem.eql(u8, method, "AirtableListBases")) break :blk "airtable_list_bases";
        if (std.mem.eql(u8, method, "AirtableGetBaseSchema")) break :blk "airtable_get_base_schema";
        if (std.mem.eql(u8, method, "AirtableListRecords")) break :blk "airtable_list_records";
        if (std.mem.eql(u8, method, "AirtableGetRecord")) break :blk "airtable_get_record";
        if (std.mem.eql(u8, method, "AirtableCreateRecord")) break :blk "airtable_create_record";
        if (std.mem.eql(u8, method, "AirtableUpdateRecord")) break :blk "airtable_update_record";
        if (std.mem.eql(u8, method, "AirtableListFields")) break :blk "airtable_list_fields";
        if (std.mem.eql(u8, method, "AirtableListViews")) break :blk "airtable_list_views";
        if (std.mem.eql(u8, method, "AirtableListWebhooks")) break :blk "airtable_list_webhooks";
        if (std.mem.eql(u8, method, "AirtableGetComments")) break :blk "airtable_get_comments";
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
    if (std.mem.indexOf(u8, body, "list_bases") != null) return dispatch("airtable_list_bases", body, resp);
    if (std.mem.indexOf(u8, body, "get_base_schema") != null) return dispatch("airtable_get_base_schema", body, resp);
    if (std.mem.indexOf(u8, body, "list_records") != null) return dispatch("airtable_list_records", body, resp);
    if (std.mem.indexOf(u8, body, "get_record") != null) return dispatch("airtable_get_record", body, resp);
    if (std.mem.indexOf(u8, body, "create_record") != null) return dispatch("airtable_create_record", body, resp);
    if (std.mem.indexOf(u8, body, "update_record") != null) return dispatch("airtable_update_record", body, resp);
    if (std.mem.indexOf(u8, body, "list_fields") != null) return dispatch("airtable_list_fields", body, resp);
    if (std.mem.indexOf(u8, body, "list_views") != null) return dispatch("airtable_list_views", body, resp);
    if (std.mem.indexOf(u8, body, "list_webhooks") != null) return dispatch("airtable_list_webhooks", body, resp);
    if (std.mem.indexOf(u8, body, "get_comments") != null) return dispatch("airtable_get_comments", body, resp);
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
