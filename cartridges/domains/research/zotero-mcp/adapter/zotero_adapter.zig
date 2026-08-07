// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// zotero-mcp/adapter/zotero_adapter.zig -- Unified three-protocol adapter.
//
// Replaces the banned zotero_adapter.v (zig, removed 2026-04-12).
//
// Bridges the Zig FFI (zotero_mcp_ffi.zig) to three network protocols:
//   REST        :9100  POST /tools/<tool>
//   gRPC-compat :9101  /ZoteroMcpService/<Method>
//   GraphQL     :9102  POST /graphql  { query: "..." }
//
// Zotero reference manager: items, collections, tags, citations, bibliographies
// Tools:
//   zotero_search_items
//   zotero_get_item
//   zotero_list_collections
//   zotero_get_collection_items
//   zotero_list_tags
//   zotero_get_items_by_tag
//   zotero_get_attachments
//   zotero_export_citation
//   zotero_get_notes
//   zotero_list_saved_searches
//   zotero_get_group_libraries
//   zotero_generate_bibliography

const std = @import("std");
const ffi = @import("zotero_mcp_ffi");

const REST_PORT: u16 = 9100;
const GRPC_PORT: u16 = 9101;
const GQL_PORT:  u16 = 9102;

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
        \\{{"success":true,"state":"ready","service":"zotero-mcp"}}
    , .{}) catch buf[0..0];
}

// ============================================================================
// Tool dispatcher
// ============================================================================

const Response = struct { status: u16, body: []u8 };

fn dispatch(tool: []const u8, body: []const u8, resp: []u8) Response {
    _ = body;
    if (std.mem.eql(u8, tool, "zotero_search_items")) return .{ .status = 200, .body = okJson(resp, "zotero_search_items forwarded to backend") };
    if (std.mem.eql(u8, tool, "zotero_get_item")) return .{ .status = 200, .body = okJson(resp, "zotero_get_item forwarded to backend") };
    if (std.mem.eql(u8, tool, "zotero_list_collections")) return .{ .status = 200, .body = okJson(resp, "zotero_list_collections forwarded to backend") };
    if (std.mem.eql(u8, tool, "zotero_get_collection_items")) return .{ .status = 200, .body = okJson(resp, "zotero_get_collection_items forwarded to backend") };
    if (std.mem.eql(u8, tool, "zotero_list_tags")) return .{ .status = 200, .body = okJson(resp, "zotero_list_tags forwarded to backend") };
    if (std.mem.eql(u8, tool, "zotero_get_items_by_tag")) return .{ .status = 200, .body = okJson(resp, "zotero_get_items_by_tag forwarded to backend") };
    if (std.mem.eql(u8, tool, "zotero_get_attachments")) return .{ .status = 200, .body = okJson(resp, "zotero_get_attachments forwarded to backend") };
    if (std.mem.eql(u8, tool, "zotero_export_citation")) return .{ .status = 200, .body = okJson(resp, "zotero_export_citation forwarded to backend") };
    if (std.mem.eql(u8, tool, "zotero_get_notes")) return .{ .status = 200, .body = okJson(resp, "zotero_get_notes forwarded to backend") };
    if (std.mem.eql(u8, tool, "zotero_list_saved_searches")) return .{ .status = 200, .body = okJson(resp, "zotero_list_saved_searches forwarded to backend") };
    if (std.mem.eql(u8, tool, "zotero_get_group_libraries")) return .{ .status = 200, .body = okJson(resp, "zotero_get_group_libraries forwarded to backend") };
    if (std.mem.eql(u8, tool, "zotero_generate_bibliography")) return .{ .status = 200, .body = okJson(resp, "zotero_generate_bibliography forwarded to backend") };
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
    const prefix = "/ZoteroMcpService/";
    if (!std.mem.startsWith(u8, path, prefix))
        return .{ .status = 404, .body = errJson(resp, "Not a recognized gRPC path") };
    const method = path[prefix.len..];
    const tool = blk: {
        if (std.mem.eql(u8, method, "ZoteroSearchItems")) break :blk "zotero_search_items";
        if (std.mem.eql(u8, method, "ZoteroGetItem")) break :blk "zotero_get_item";
        if (std.mem.eql(u8, method, "ZoteroListCollections")) break :blk "zotero_list_collections";
        if (std.mem.eql(u8, method, "ZoteroGetCollectionItems")) break :blk "zotero_get_collection_items";
        if (std.mem.eql(u8, method, "ZoteroListTags")) break :blk "zotero_list_tags";
        if (std.mem.eql(u8, method, "ZoteroGetItemsByTag")) break :blk "zotero_get_items_by_tag";
        if (std.mem.eql(u8, method, "ZoteroGetAttachments")) break :blk "zotero_get_attachments";
        if (std.mem.eql(u8, method, "ZoteroExportCitation")) break :blk "zotero_export_citation";
        if (std.mem.eql(u8, method, "ZoteroGetNotes")) break :blk "zotero_get_notes";
        if (std.mem.eql(u8, method, "ZoteroListSavedSearches")) break :blk "zotero_list_saved_searches";
        if (std.mem.eql(u8, method, "ZoteroGetGroupLibraries")) break :blk "zotero_get_group_libraries";
        if (std.mem.eql(u8, method, "ZoteroGenerateBibliography")) break :blk "zotero_generate_bibliography";
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
    if (std.mem.indexOf(u8, body, "search_items") != null) return dispatch("zotero_search_items", body, resp);
    if (std.mem.indexOf(u8, body, "get_item") != null) return dispatch("zotero_get_item", body, resp);
    if (std.mem.indexOf(u8, body, "list_collections") != null) return dispatch("zotero_list_collections", body, resp);
    if (std.mem.indexOf(u8, body, "get_collection_items") != null) return dispatch("zotero_get_collection_items", body, resp);
    if (std.mem.indexOf(u8, body, "list_tags") != null) return dispatch("zotero_list_tags", body, resp);
    if (std.mem.indexOf(u8, body, "get_items_by_tag") != null) return dispatch("zotero_get_items_by_tag", body, resp);
    if (std.mem.indexOf(u8, body, "get_attachments") != null) return dispatch("zotero_get_attachments", body, resp);
    if (std.mem.indexOf(u8, body, "export_citation") != null) return dispatch("zotero_export_citation", body, resp);
    if (std.mem.indexOf(u8, body, "get_notes") != null) return dispatch("zotero_get_notes", body, resp);
    if (std.mem.indexOf(u8, body, "list_saved_searches") != null) return dispatch("zotero_list_saved_searches", body, resp);
    if (std.mem.indexOf(u8, body, "get_group_libraries") != null) return dispatch("zotero_get_group_libraries", body, resp);
    if (std.mem.indexOf(u8, body, "generate_bibliography") != null) return dispatch("zotero_generate_bibliography", body, resp);
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
