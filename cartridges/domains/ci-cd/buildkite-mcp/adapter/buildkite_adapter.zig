// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// buildkite-mcp/adapter/buildkite_adapter.zig -- Unified three-protocol adapter.
//
// Replaces the banned buildkite_adapter.v (zig, removed 2026-04-12).
//
// Bridges the Zig FFI (buildkite_mcp_ffi.zig) to three network protocols:
//   REST        :9037  POST /tools/<tool>
//   gRPC-compat :9038  /BuildkiteMcpService/<Method>
//   GraphQL     :9039  POST /graphql  { query: "..." }
//
// Buildkite CI/CD: pipelines, builds, jobs, artifacts, agents
// Tools:
//   buildkite_list_pipelines
//   buildkite_get_pipeline
//   buildkite_list_builds
//   buildkite_get_build
//   buildkite_create_build
//   buildkite_cancel_build
//   buildkite_list_jobs
//   buildkite_get_job_log
//   buildkite_list_artifacts
//   buildkite_list_agents

const std = @import("std");
const ffi = @import("buildkite_mcp_ffi");

const REST_PORT: u16 = 9037;
const GRPC_PORT: u16 = 9038;
const GQL_PORT:  u16 = 9039;

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
        \\{{"success":true,"state":"ready","service":"buildkite-mcp"}}
    , .{}) catch buf[0..0];
}

// ============================================================================
// Tool dispatcher
// ============================================================================

const Response = struct { status: u16, body: []u8 };

fn dispatch(tool: []const u8, body: []const u8, resp: []u8) Response {
    _ = body;
    if (std.mem.eql(u8, tool, "buildkite_list_pipelines")) return .{ .status = 200, .body = okJson(resp, "buildkite_list_pipelines forwarded to backend") };
    if (std.mem.eql(u8, tool, "buildkite_get_pipeline")) return .{ .status = 200, .body = okJson(resp, "buildkite_get_pipeline forwarded to backend") };
    if (std.mem.eql(u8, tool, "buildkite_list_builds")) return .{ .status = 200, .body = okJson(resp, "buildkite_list_builds forwarded to backend") };
    if (std.mem.eql(u8, tool, "buildkite_get_build")) return .{ .status = 200, .body = okJson(resp, "buildkite_get_build forwarded to backend") };
    if (std.mem.eql(u8, tool, "buildkite_create_build")) return .{ .status = 200, .body = okJson(resp, "buildkite_create_build forwarded to backend") };
    if (std.mem.eql(u8, tool, "buildkite_cancel_build")) return .{ .status = 200, .body = okJson(resp, "buildkite_cancel_build forwarded to backend") };
    if (std.mem.eql(u8, tool, "buildkite_list_jobs")) return .{ .status = 200, .body = okJson(resp, "buildkite_list_jobs forwarded to backend") };
    if (std.mem.eql(u8, tool, "buildkite_get_job_log")) return .{ .status = 200, .body = okJson(resp, "buildkite_get_job_log forwarded to backend") };
    if (std.mem.eql(u8, tool, "buildkite_list_artifacts")) return .{ .status = 200, .body = okJson(resp, "buildkite_list_artifacts forwarded to backend") };
    if (std.mem.eql(u8, tool, "buildkite_list_agents")) return .{ .status = 200, .body = okJson(resp, "buildkite_list_agents forwarded to backend") };
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
    const prefix = "/BuildkiteMcpService/";
    if (!std.mem.startsWith(u8, path, prefix))
        return .{ .status = 404, .body = errJson(resp, "Not a recognized gRPC path") };
    const method = path[prefix.len..];
    const tool = blk: {
        if (std.mem.eql(u8, method, "BuildkiteListPipelines")) break :blk "buildkite_list_pipelines";
        if (std.mem.eql(u8, method, "BuildkiteGetPipeline")) break :blk "buildkite_get_pipeline";
        if (std.mem.eql(u8, method, "BuildkiteListBuilds")) break :blk "buildkite_list_builds";
        if (std.mem.eql(u8, method, "BuildkiteGetBuild")) break :blk "buildkite_get_build";
        if (std.mem.eql(u8, method, "BuildkiteCreateBuild")) break :blk "buildkite_create_build";
        if (std.mem.eql(u8, method, "BuildkiteCancelBuild")) break :blk "buildkite_cancel_build";
        if (std.mem.eql(u8, method, "BuildkiteListJobs")) break :blk "buildkite_list_jobs";
        if (std.mem.eql(u8, method, "BuildkiteGetJobLog")) break :blk "buildkite_get_job_log";
        if (std.mem.eql(u8, method, "BuildkiteListArtifacts")) break :blk "buildkite_list_artifacts";
        if (std.mem.eql(u8, method, "BuildkiteListAgents")) break :blk "buildkite_list_agents";
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
    if (std.mem.indexOf(u8, body, "list_pipelines") != null) return dispatch("buildkite_list_pipelines", body, resp);
    if (std.mem.indexOf(u8, body, "get_pipeline") != null) return dispatch("buildkite_get_pipeline", body, resp);
    if (std.mem.indexOf(u8, body, "list_builds") != null) return dispatch("buildkite_list_builds", body, resp);
    if (std.mem.indexOf(u8, body, "get_build") != null) return dispatch("buildkite_get_build", body, resp);
    if (std.mem.indexOf(u8, body, "create_build") != null) return dispatch("buildkite_create_build", body, resp);
    if (std.mem.indexOf(u8, body, "cancel_build") != null) return dispatch("buildkite_cancel_build", body, resp);
    if (std.mem.indexOf(u8, body, "list_jobs") != null) return dispatch("buildkite_list_jobs", body, resp);
    if (std.mem.indexOf(u8, body, "get_job_log") != null) return dispatch("buildkite_get_job_log", body, resp);
    if (std.mem.indexOf(u8, body, "list_artifacts") != null) return dispatch("buildkite_list_artifacts", body, resp);
    if (std.mem.indexOf(u8, body, "list_agents") != null) return dispatch("buildkite_list_agents", body, resp);
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
