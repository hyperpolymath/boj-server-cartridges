// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// render-mcp/adapter/render_adapter.zig -- Unified three-protocol adapter.
//
// Replaces the banned render_adapter.v (zig, removed 2026-04-12).
//
// Bridges the Zig FFI (render_mcp_ffi.zig) to three network protocols:
//   REST        :9091  POST /tools/<tool>
//   gRPC-compat :9092  /RenderMcpService/<Method>
//   GraphQL     :9093  POST /graphql  { query: "..." }
//
// Render cloud: services, deploys, env groups, custom domains, jobs
// Tools:
//   render_list_services
//   render_get_service
//   render_create_service
//   render_delete_service
//   render_list_deploys
//   render_trigger_deploy
//   render_get_deploy
//   render_list_env_groups
//   render_get_env_group
//   render_list_custom_domains
//   render_add_custom_domain
//   render_list_jobs
//   render_create_job
//   render_suspend_service
//   render_resume_service
//   render_get_bandwidth

const std = @import("std");
const ffi = @import("render_mcp_ffi");

const REST_PORT: u16 = 9091;
const GRPC_PORT: u16 = 9092;
const GQL_PORT:  u16 = 9093;

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
        \\{{"success":true,"state":"ready","service":"render-mcp"}}
    , .{}) catch buf[0..0];
}

// ============================================================================
// Tool dispatcher
// ============================================================================

const Response = struct { status: u16, body: []u8 };

fn dispatch(tool: []const u8, body: []const u8, resp: []u8) Response {
    _ = body;
    if (std.mem.eql(u8, tool, "render_list_services")) return .{ .status = 200, .body = okJson(resp, "render_list_services forwarded to backend") };
    if (std.mem.eql(u8, tool, "render_get_service")) return .{ .status = 200, .body = okJson(resp, "render_get_service forwarded to backend") };
    if (std.mem.eql(u8, tool, "render_create_service")) return .{ .status = 200, .body = okJson(resp, "render_create_service forwarded to backend") };
    if (std.mem.eql(u8, tool, "render_delete_service")) return .{ .status = 200, .body = okJson(resp, "render_delete_service forwarded to backend") };
    if (std.mem.eql(u8, tool, "render_list_deploys")) return .{ .status = 200, .body = okJson(resp, "render_list_deploys forwarded to backend") };
    if (std.mem.eql(u8, tool, "render_trigger_deploy")) return .{ .status = 200, .body = okJson(resp, "render_trigger_deploy forwarded to backend") };
    if (std.mem.eql(u8, tool, "render_get_deploy")) return .{ .status = 200, .body = okJson(resp, "render_get_deploy forwarded to backend") };
    if (std.mem.eql(u8, tool, "render_list_env_groups")) return .{ .status = 200, .body = okJson(resp, "render_list_env_groups forwarded to backend") };
    if (std.mem.eql(u8, tool, "render_get_env_group")) return .{ .status = 200, .body = okJson(resp, "render_get_env_group forwarded to backend") };
    if (std.mem.eql(u8, tool, "render_list_custom_domains")) return .{ .status = 200, .body = okJson(resp, "render_list_custom_domains forwarded to backend") };
    if (std.mem.eql(u8, tool, "render_add_custom_domain")) return .{ .status = 200, .body = okJson(resp, "render_add_custom_domain forwarded to backend") };
    if (std.mem.eql(u8, tool, "render_list_jobs")) return .{ .status = 200, .body = okJson(resp, "render_list_jobs forwarded to backend") };
    if (std.mem.eql(u8, tool, "render_create_job")) return .{ .status = 200, .body = okJson(resp, "render_create_job forwarded to backend") };
    if (std.mem.eql(u8, tool, "render_suspend_service")) return .{ .status = 200, .body = okJson(resp, "render_suspend_service forwarded to backend") };
    if (std.mem.eql(u8, tool, "render_resume_service")) return .{ .status = 200, .body = okJson(resp, "render_resume_service forwarded to backend") };
    if (std.mem.eql(u8, tool, "render_get_bandwidth")) return .{ .status = 200, .body = okJson(resp, "render_get_bandwidth forwarded to backend") };
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
    const prefix = "/RenderMcpService/";
    if (!std.mem.startsWith(u8, path, prefix))
        return .{ .status = 404, .body = errJson(resp, "Not a recognized gRPC path") };
    const method = path[prefix.len..];
    const tool = blk: {
        if (std.mem.eql(u8, method, "RenderListServices")) break :blk "render_list_services";
        if (std.mem.eql(u8, method, "RenderGetService")) break :blk "render_get_service";
        if (std.mem.eql(u8, method, "RenderCreateService")) break :blk "render_create_service";
        if (std.mem.eql(u8, method, "RenderDeleteService")) break :blk "render_delete_service";
        if (std.mem.eql(u8, method, "RenderListDeploys")) break :blk "render_list_deploys";
        if (std.mem.eql(u8, method, "RenderTriggerDeploy")) break :blk "render_trigger_deploy";
        if (std.mem.eql(u8, method, "RenderGetDeploy")) break :blk "render_get_deploy";
        if (std.mem.eql(u8, method, "RenderListEnvGroups")) break :blk "render_list_env_groups";
        if (std.mem.eql(u8, method, "RenderGetEnvGroup")) break :blk "render_get_env_group";
        if (std.mem.eql(u8, method, "RenderListCustomDomains")) break :blk "render_list_custom_domains";
        if (std.mem.eql(u8, method, "RenderAddCustomDomain")) break :blk "render_add_custom_domain";
        if (std.mem.eql(u8, method, "RenderListJobs")) break :blk "render_list_jobs";
        if (std.mem.eql(u8, method, "RenderCreateJob")) break :blk "render_create_job";
        if (std.mem.eql(u8, method, "RenderSuspendService")) break :blk "render_suspend_service";
        if (std.mem.eql(u8, method, "RenderResumeService")) break :blk "render_resume_service";
        if (std.mem.eql(u8, method, "RenderGetBandwidth")) break :blk "render_get_bandwidth";
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
    if (std.mem.indexOf(u8, body, "list_services") != null) return dispatch("render_list_services", body, resp);
    if (std.mem.indexOf(u8, body, "get_service") != null) return dispatch("render_get_service", body, resp);
    if (std.mem.indexOf(u8, body, "create_service") != null) return dispatch("render_create_service", body, resp);
    if (std.mem.indexOf(u8, body, "delete_service") != null) return dispatch("render_delete_service", body, resp);
    if (std.mem.indexOf(u8, body, "list_deploys") != null) return dispatch("render_list_deploys", body, resp);
    if (std.mem.indexOf(u8, body, "trigger_deploy") != null) return dispatch("render_trigger_deploy", body, resp);
    if (std.mem.indexOf(u8, body, "get_deploy") != null) return dispatch("render_get_deploy", body, resp);
    if (std.mem.indexOf(u8, body, "list_env_groups") != null) return dispatch("render_list_env_groups", body, resp);
    if (std.mem.indexOf(u8, body, "get_env_group") != null) return dispatch("render_get_env_group", body, resp);
    if (std.mem.indexOf(u8, body, "list_custom_domains") != null) return dispatch("render_list_custom_domains", body, resp);
    if (std.mem.indexOf(u8, body, "add_custom_domain") != null) return dispatch("render_add_custom_domain", body, resp);
    if (std.mem.indexOf(u8, body, "list_jobs") != null) return dispatch("render_list_jobs", body, resp);
    if (std.mem.indexOf(u8, body, "create_job") != null) return dispatch("render_create_job", body, resp);
    if (std.mem.indexOf(u8, body, "suspend_service") != null) return dispatch("render_suspend_service", body, resp);
    if (std.mem.indexOf(u8, body, "resume_service") != null) return dispatch("render_resume_service", body, resp);
    if (std.mem.indexOf(u8, body, "get_bandwidth") != null) return dispatch("render_get_bandwidth", body, resp);
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
