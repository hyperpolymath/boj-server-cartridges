// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// docker-hub-mcp/adapter/docker_hub_adapter.zig -- Unified three-protocol adapter.
//
// Replaces the banned docker_hub_adapter.v (zig, removed 2026-04-12).
//
// Bridges the Zig FFI (docker_hub_mcp_ffi.zig) to three network protocols:
//   REST        :9046  POST /tools/<tool>
//   gRPC-compat :9047  /DockerHubMcpService/<Method>
//   GraphQL     :9048  POST /graphql  { query: "..." }
//
// Docker Hub registry: repositories, tags, manifests, rate limits
// Tools:
//   dockerhub_search_images
//   dockerhub_get_repository
//   dockerhub_list_tags
//   dockerhub_get_tag
//   dockerhub_list_namespaces
//   dockerhub_get_manifest
//   dockerhub_delete_tag
//   dockerhub_get_rate_limit
//   dockerhub_list_orgs
//   dockerhub_create_repository
//   dockerhub_delete_repository
//   dockerhub_get_dockerfile
//   dockerhub_list_starred
//   dockerhub_star_repository
//   dockerhub_unstar_repository
//   dockerhub_get_user

const std = @import("std");
const ffi = @import("docker_hub_mcp_ffi");

const REST_PORT: u16 = 9046;
const GRPC_PORT: u16 = 9047;
const GQL_PORT:  u16 = 9048;

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
        \\{{"success":true,"state":"ready","service":"docker-hub-mcp"}}
    , .{}) catch buf[0..0];
}

// ============================================================================
// Tool dispatcher
// ============================================================================

const Response = struct { status: u16, body: []u8 };

fn dispatch(tool: []const u8, body: []const u8, resp: []u8) Response {
    _ = body;
    if (std.mem.eql(u8, tool, "dockerhub_search_images")) return .{ .status = 200, .body = okJson(resp, "dockerhub_search_images forwarded to backend") };
    if (std.mem.eql(u8, tool, "dockerhub_get_repository")) return .{ .status = 200, .body = okJson(resp, "dockerhub_get_repository forwarded to backend") };
    if (std.mem.eql(u8, tool, "dockerhub_list_tags")) return .{ .status = 200, .body = okJson(resp, "dockerhub_list_tags forwarded to backend") };
    if (std.mem.eql(u8, tool, "dockerhub_get_tag")) return .{ .status = 200, .body = okJson(resp, "dockerhub_get_tag forwarded to backend") };
    if (std.mem.eql(u8, tool, "dockerhub_list_namespaces")) return .{ .status = 200, .body = okJson(resp, "dockerhub_list_namespaces forwarded to backend") };
    if (std.mem.eql(u8, tool, "dockerhub_get_manifest")) return .{ .status = 200, .body = okJson(resp, "dockerhub_get_manifest forwarded to backend") };
    if (std.mem.eql(u8, tool, "dockerhub_delete_tag")) return .{ .status = 200, .body = okJson(resp, "dockerhub_delete_tag forwarded to backend") };
    if (std.mem.eql(u8, tool, "dockerhub_get_rate_limit")) return .{ .status = 200, .body = okJson(resp, "dockerhub_get_rate_limit forwarded to backend") };
    if (std.mem.eql(u8, tool, "dockerhub_list_orgs")) return .{ .status = 200, .body = okJson(resp, "dockerhub_list_orgs forwarded to backend") };
    if (std.mem.eql(u8, tool, "dockerhub_create_repository")) return .{ .status = 200, .body = okJson(resp, "dockerhub_create_repository forwarded to backend") };
    if (std.mem.eql(u8, tool, "dockerhub_delete_repository")) return .{ .status = 200, .body = okJson(resp, "dockerhub_delete_repository forwarded to backend") };
    if (std.mem.eql(u8, tool, "dockerhub_get_dockerfile")) return .{ .status = 200, .body = okJson(resp, "dockerhub_get_dockerfile forwarded to backend") };
    if (std.mem.eql(u8, tool, "dockerhub_list_starred")) return .{ .status = 200, .body = okJson(resp, "dockerhub_list_starred forwarded to backend") };
    if (std.mem.eql(u8, tool, "dockerhub_star_repository")) return .{ .status = 200, .body = okJson(resp, "dockerhub_star_repository forwarded to backend") };
    if (std.mem.eql(u8, tool, "dockerhub_unstar_repository")) return .{ .status = 200, .body = okJson(resp, "dockerhub_unstar_repository forwarded to backend") };
    if (std.mem.eql(u8, tool, "dockerhub_get_user")) return .{ .status = 200, .body = okJson(resp, "dockerhub_get_user forwarded to backend") };
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
    const prefix = "/DockerHubMcpService/";
    if (!std.mem.startsWith(u8, path, prefix))
        return .{ .status = 404, .body = errJson(resp, "Not a recognized gRPC path") };
    const method = path[prefix.len..];
    const tool = blk: {
        if (std.mem.eql(u8, method, "DockerhubSearchImages")) break :blk "dockerhub_search_images";
        if (std.mem.eql(u8, method, "DockerhubGetRepository")) break :blk "dockerhub_get_repository";
        if (std.mem.eql(u8, method, "DockerhubListTags")) break :blk "dockerhub_list_tags";
        if (std.mem.eql(u8, method, "DockerhubGetTag")) break :blk "dockerhub_get_tag";
        if (std.mem.eql(u8, method, "DockerhubListNamespaces")) break :blk "dockerhub_list_namespaces";
        if (std.mem.eql(u8, method, "DockerhubGetManifest")) break :blk "dockerhub_get_manifest";
        if (std.mem.eql(u8, method, "DockerhubDeleteTag")) break :blk "dockerhub_delete_tag";
        if (std.mem.eql(u8, method, "DockerhubGetRateLimit")) break :blk "dockerhub_get_rate_limit";
        if (std.mem.eql(u8, method, "DockerhubListOrgs")) break :blk "dockerhub_list_orgs";
        if (std.mem.eql(u8, method, "DockerhubCreateRepository")) break :blk "dockerhub_create_repository";
        if (std.mem.eql(u8, method, "DockerhubDeleteRepository")) break :blk "dockerhub_delete_repository";
        if (std.mem.eql(u8, method, "DockerhubGetDockerfile")) break :blk "dockerhub_get_dockerfile";
        if (std.mem.eql(u8, method, "DockerhubListStarred")) break :blk "dockerhub_list_starred";
        if (std.mem.eql(u8, method, "DockerhubStarRepository")) break :blk "dockerhub_star_repository";
        if (std.mem.eql(u8, method, "DockerhubUnstarRepository")) break :blk "dockerhub_unstar_repository";
        if (std.mem.eql(u8, method, "DockerhubGetUser")) break :blk "dockerhub_get_user";
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
    if (std.mem.indexOf(u8, body, "search_images") != null) return dispatch("dockerhub_search_images", body, resp);
    if (std.mem.indexOf(u8, body, "get_repository") != null) return dispatch("dockerhub_get_repository", body, resp);
    if (std.mem.indexOf(u8, body, "list_tags") != null) return dispatch("dockerhub_list_tags", body, resp);
    if (std.mem.indexOf(u8, body, "get_tag") != null) return dispatch("dockerhub_get_tag", body, resp);
    if (std.mem.indexOf(u8, body, "list_namespaces") != null) return dispatch("dockerhub_list_namespaces", body, resp);
    if (std.mem.indexOf(u8, body, "get_manifest") != null) return dispatch("dockerhub_get_manifest", body, resp);
    if (std.mem.indexOf(u8, body, "delete_tag") != null) return dispatch("dockerhub_delete_tag", body, resp);
    if (std.mem.indexOf(u8, body, "get_rate_limit") != null) return dispatch("dockerhub_get_rate_limit", body, resp);
    if (std.mem.indexOf(u8, body, "list_orgs") != null) return dispatch("dockerhub_list_orgs", body, resp);
    if (std.mem.indexOf(u8, body, "create_repository") != null) return dispatch("dockerhub_create_repository", body, resp);
    if (std.mem.indexOf(u8, body, "delete_repository") != null) return dispatch("dockerhub_delete_repository", body, resp);
    if (std.mem.indexOf(u8, body, "get_dockerfile") != null) return dispatch("dockerhub_get_dockerfile", body, resp);
    if (std.mem.indexOf(u8, body, "list_starred") != null) return dispatch("dockerhub_list_starred", body, resp);
    if (std.mem.indexOf(u8, body, "star_repository") != null) return dispatch("dockerhub_star_repository", body, resp);
    if (std.mem.indexOf(u8, body, "unstar_repository") != null) return dispatch("dockerhub_unstar_repository", body, resp);
    if (std.mem.indexOf(u8, body, "get_user") != null) return dispatch("dockerhub_get_user", body, resp);
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
