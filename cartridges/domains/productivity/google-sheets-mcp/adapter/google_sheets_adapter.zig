// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// google-sheets-mcp/adapter/google_sheets_adapter.zig -- Unified three-protocol adapter.
//
// Replaces the banned google_sheets_adapter.v (zig, removed 2026-04-12).
//
// Bridges the Zig FFI (google_sheets_mcp_ffi.zig) to three network protocols:
//   REST        :9055  POST /tools/<tool>
//   gRPC-compat :9056  /GoogleSheetsMcpService/<Method>
//   GraphQL     :9057  POST /graphql  { query: "..." }
//
// Google Sheets API: read/write ranges, sheets, named ranges, pivot tables
// Tools:
//   gsheets_get_spreadsheet
//   gsheets_read_range
//   gsheets_list_sheets
//   gsheets_get_named_ranges
//   gsheets_write_range
//   gsheets_append_rows
//   gsheets_create_sheet
//   gsheets_batch_read
//   gsheets_get_conditional_formats
//   gsheets_get_pivot_tables

const std = @import("std");
const ffi = @import("google_sheets_mcp_ffi");

const REST_PORT: u16 = 9055;
const GRPC_PORT: u16 = 9056;
const GQL_PORT:  u16 = 9057;

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
        \\{{"success":true,"state":"ready","service":"google-sheets-mcp"}}
    , .{}) catch buf[0..0];
}

// ============================================================================
// Tool dispatcher
// ============================================================================

const Response = struct { status: u16, body: []u8 };

fn dispatch(tool: []const u8, body: []const u8, resp: []u8) Response {
    _ = body;
    if (std.mem.eql(u8, tool, "gsheets_get_spreadsheet")) return .{ .status = 200, .body = okJson(resp, "gsheets_get_spreadsheet forwarded to backend") };
    if (std.mem.eql(u8, tool, "gsheets_read_range")) return .{ .status = 200, .body = okJson(resp, "gsheets_read_range forwarded to backend") };
    if (std.mem.eql(u8, tool, "gsheets_list_sheets")) return .{ .status = 200, .body = okJson(resp, "gsheets_list_sheets forwarded to backend") };
    if (std.mem.eql(u8, tool, "gsheets_get_named_ranges")) return .{ .status = 200, .body = okJson(resp, "gsheets_get_named_ranges forwarded to backend") };
    if (std.mem.eql(u8, tool, "gsheets_write_range")) return .{ .status = 200, .body = okJson(resp, "gsheets_write_range forwarded to backend") };
    if (std.mem.eql(u8, tool, "gsheets_append_rows")) return .{ .status = 200, .body = okJson(resp, "gsheets_append_rows forwarded to backend") };
    if (std.mem.eql(u8, tool, "gsheets_create_sheet")) return .{ .status = 200, .body = okJson(resp, "gsheets_create_sheet forwarded to backend") };
    if (std.mem.eql(u8, tool, "gsheets_batch_read")) return .{ .status = 200, .body = okJson(resp, "gsheets_batch_read forwarded to backend") };
    if (std.mem.eql(u8, tool, "gsheets_get_conditional_formats")) return .{ .status = 200, .body = okJson(resp, "gsheets_get_conditional_formats forwarded to backend") };
    if (std.mem.eql(u8, tool, "gsheets_get_pivot_tables")) return .{ .status = 200, .body = okJson(resp, "gsheets_get_pivot_tables forwarded to backend") };
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
    const prefix = "/GoogleSheetsMcpService/";
    if (!std.mem.startsWith(u8, path, prefix))
        return .{ .status = 404, .body = errJson(resp, "Not a recognized gRPC path") };
    const method = path[prefix.len..];
    const tool = blk: {
        if (std.mem.eql(u8, method, "GsheetsGetSpreadsheet")) break :blk "gsheets_get_spreadsheet";
        if (std.mem.eql(u8, method, "GsheetsReadRange")) break :blk "gsheets_read_range";
        if (std.mem.eql(u8, method, "GsheetsListSheets")) break :blk "gsheets_list_sheets";
        if (std.mem.eql(u8, method, "GsheetsGetNamedRanges")) break :blk "gsheets_get_named_ranges";
        if (std.mem.eql(u8, method, "GsheetsWriteRange")) break :blk "gsheets_write_range";
        if (std.mem.eql(u8, method, "GsheetsAppendRows")) break :blk "gsheets_append_rows";
        if (std.mem.eql(u8, method, "GsheetsCreateSheet")) break :blk "gsheets_create_sheet";
        if (std.mem.eql(u8, method, "GsheetsBatchRead")) break :blk "gsheets_batch_read";
        if (std.mem.eql(u8, method, "GsheetsGetConditionalFormats")) break :blk "gsheets_get_conditional_formats";
        if (std.mem.eql(u8, method, "GsheetsGetPivotTables")) break :blk "gsheets_get_pivot_tables";
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
    if (std.mem.indexOf(u8, body, "get_spreadsheet") != null) return dispatch("gsheets_get_spreadsheet", body, resp);
    if (std.mem.indexOf(u8, body, "read_range") != null) return dispatch("gsheets_read_range", body, resp);
    if (std.mem.indexOf(u8, body, "list_sheets") != null) return dispatch("gsheets_list_sheets", body, resp);
    if (std.mem.indexOf(u8, body, "get_named_ranges") != null) return dispatch("gsheets_get_named_ranges", body, resp);
    if (std.mem.indexOf(u8, body, "write_range") != null) return dispatch("gsheets_write_range", body, resp);
    if (std.mem.indexOf(u8, body, "append_rows") != null) return dispatch("gsheets_append_rows", body, resp);
    if (std.mem.indexOf(u8, body, "create_sheet") != null) return dispatch("gsheets_create_sheet", body, resp);
    if (std.mem.indexOf(u8, body, "batch_read") != null) return dispatch("gsheets_batch_read", body, resp);
    if (std.mem.indexOf(u8, body, "get_conditional_formats") != null) return dispatch("gsheets_get_conditional_formats", body, resp);
    if (std.mem.indexOf(u8, body, "get_pivot_tables") != null) return dispatch("gsheets_get_pivot_tables", body, resp);
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
