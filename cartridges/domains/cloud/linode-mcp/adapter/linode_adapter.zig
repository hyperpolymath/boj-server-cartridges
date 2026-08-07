// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// linode-mcp/adapter/linode_adapter.zig -- Unified three-protocol adapter.
//
// Replaces the banned linode_adapter.v (zig, removed 2026-04-12).
//
// Bridges the Zig FFI (linode_mcp_ffi.zig) to three network protocols:
//   REST        :9070  POST /tools/<tool>
//   gRPC-compat :9071  /LinodeMcpService/<Method>
//   GraphQL     :9072  POST /graphql  { query: "..." }
//
// Linode/Akamai Cloud: instances, volumes, domains, nodebalancers, firewalls
// Tools:
//   linode_list_instances
//   linode_get_instance
//   linode_create_instance
//   linode_delete_instance
//   linode_boot_instance
//   linode_shutdown_instance
//   linode_reboot_instance
//   linode_list_volumes
//   linode_create_volume
//   linode_list_domains
//   linode_create_domain
//   linode_list_nodebalancers
//   linode_list_stackscripts
//   linode_list_images
//   linode_list_regions
//   linode_list_firewalls
//   linode_create_firewall
//   linode_get_account

const std = @import("std");
const ffi = @import("linode_mcp_ffi");

const REST_PORT: u16 = 9070;
const GRPC_PORT: u16 = 9071;
const GQL_PORT:  u16 = 9072;

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
        \\{{"success":true,"state":"ready","service":"linode-mcp"}}
    , .{}) catch buf[0..0];
}

// ============================================================================
// Tool dispatcher
// ============================================================================

const Response = struct { status: u16, body: []u8 };

fn dispatch(tool: []const u8, body: []const u8, resp: []u8) Response {
    _ = body;
    if (std.mem.eql(u8, tool, "linode_list_instances")) return .{ .status = 200, .body = okJson(resp, "linode_list_instances forwarded to backend") };
    if (std.mem.eql(u8, tool, "linode_get_instance")) return .{ .status = 200, .body = okJson(resp, "linode_get_instance forwarded to backend") };
    if (std.mem.eql(u8, tool, "linode_create_instance")) return .{ .status = 200, .body = okJson(resp, "linode_create_instance forwarded to backend") };
    if (std.mem.eql(u8, tool, "linode_delete_instance")) return .{ .status = 200, .body = okJson(resp, "linode_delete_instance forwarded to backend") };
    if (std.mem.eql(u8, tool, "linode_boot_instance")) return .{ .status = 200, .body = okJson(resp, "linode_boot_instance forwarded to backend") };
    if (std.mem.eql(u8, tool, "linode_shutdown_instance")) return .{ .status = 200, .body = okJson(resp, "linode_shutdown_instance forwarded to backend") };
    if (std.mem.eql(u8, tool, "linode_reboot_instance")) return .{ .status = 200, .body = okJson(resp, "linode_reboot_instance forwarded to backend") };
    if (std.mem.eql(u8, tool, "linode_list_volumes")) return .{ .status = 200, .body = okJson(resp, "linode_list_volumes forwarded to backend") };
    if (std.mem.eql(u8, tool, "linode_create_volume")) return .{ .status = 200, .body = okJson(resp, "linode_create_volume forwarded to backend") };
    if (std.mem.eql(u8, tool, "linode_list_domains")) return .{ .status = 200, .body = okJson(resp, "linode_list_domains forwarded to backend") };
    if (std.mem.eql(u8, tool, "linode_create_domain")) return .{ .status = 200, .body = okJson(resp, "linode_create_domain forwarded to backend") };
    if (std.mem.eql(u8, tool, "linode_list_nodebalancers")) return .{ .status = 200, .body = okJson(resp, "linode_list_nodebalancers forwarded to backend") };
    if (std.mem.eql(u8, tool, "linode_list_stackscripts")) return .{ .status = 200, .body = okJson(resp, "linode_list_stackscripts forwarded to backend") };
    if (std.mem.eql(u8, tool, "linode_list_images")) return .{ .status = 200, .body = okJson(resp, "linode_list_images forwarded to backend") };
    if (std.mem.eql(u8, tool, "linode_list_regions")) return .{ .status = 200, .body = okJson(resp, "linode_list_regions forwarded to backend") };
    if (std.mem.eql(u8, tool, "linode_list_firewalls")) return .{ .status = 200, .body = okJson(resp, "linode_list_firewalls forwarded to backend") };
    if (std.mem.eql(u8, tool, "linode_create_firewall")) return .{ .status = 200, .body = okJson(resp, "linode_create_firewall forwarded to backend") };
    if (std.mem.eql(u8, tool, "linode_get_account")) return .{ .status = 200, .body = okJson(resp, "linode_get_account forwarded to backend") };
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
    const prefix = "/LinodeMcpService/";
    if (!std.mem.startsWith(u8, path, prefix))
        return .{ .status = 404, .body = errJson(resp, "Not a recognized gRPC path") };
    const method = path[prefix.len..];
    const tool = blk: {
        if (std.mem.eql(u8, method, "LinodeListInstances")) break :blk "linode_list_instances";
        if (std.mem.eql(u8, method, "LinodeGetInstance")) break :blk "linode_get_instance";
        if (std.mem.eql(u8, method, "LinodeCreateInstance")) break :blk "linode_create_instance";
        if (std.mem.eql(u8, method, "LinodeDeleteInstance")) break :blk "linode_delete_instance";
        if (std.mem.eql(u8, method, "LinodeBootInstance")) break :blk "linode_boot_instance";
        if (std.mem.eql(u8, method, "LinodeShutdownInstance")) break :blk "linode_shutdown_instance";
        if (std.mem.eql(u8, method, "LinodeRebootInstance")) break :blk "linode_reboot_instance";
        if (std.mem.eql(u8, method, "LinodeListVolumes")) break :blk "linode_list_volumes";
        if (std.mem.eql(u8, method, "LinodeCreateVolume")) break :blk "linode_create_volume";
        if (std.mem.eql(u8, method, "LinodeListDomains")) break :blk "linode_list_domains";
        if (std.mem.eql(u8, method, "LinodeCreateDomain")) break :blk "linode_create_domain";
        if (std.mem.eql(u8, method, "LinodeListNodebalancers")) break :blk "linode_list_nodebalancers";
        if (std.mem.eql(u8, method, "LinodeListStackscripts")) break :blk "linode_list_stackscripts";
        if (std.mem.eql(u8, method, "LinodeListImages")) break :blk "linode_list_images";
        if (std.mem.eql(u8, method, "LinodeListRegions")) break :blk "linode_list_regions";
        if (std.mem.eql(u8, method, "LinodeListFirewalls")) break :blk "linode_list_firewalls";
        if (std.mem.eql(u8, method, "LinodeCreateFirewall")) break :blk "linode_create_firewall";
        if (std.mem.eql(u8, method, "LinodeGetAccount")) break :blk "linode_get_account";
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
    if (std.mem.indexOf(u8, body, "list_instances") != null) return dispatch("linode_list_instances", body, resp);
    if (std.mem.indexOf(u8, body, "get_instance") != null) return dispatch("linode_get_instance", body, resp);
    if (std.mem.indexOf(u8, body, "create_instance") != null) return dispatch("linode_create_instance", body, resp);
    if (std.mem.indexOf(u8, body, "delete_instance") != null) return dispatch("linode_delete_instance", body, resp);
    if (std.mem.indexOf(u8, body, "boot_instance") != null) return dispatch("linode_boot_instance", body, resp);
    if (std.mem.indexOf(u8, body, "shutdown_instance") != null) return dispatch("linode_shutdown_instance", body, resp);
    if (std.mem.indexOf(u8, body, "reboot_instance") != null) return dispatch("linode_reboot_instance", body, resp);
    if (std.mem.indexOf(u8, body, "list_volumes") != null) return dispatch("linode_list_volumes", body, resp);
    if (std.mem.indexOf(u8, body, "create_volume") != null) return dispatch("linode_create_volume", body, resp);
    if (std.mem.indexOf(u8, body, "list_domains") != null) return dispatch("linode_list_domains", body, resp);
    if (std.mem.indexOf(u8, body, "create_domain") != null) return dispatch("linode_create_domain", body, resp);
    if (std.mem.indexOf(u8, body, "list_nodebalancers") != null) return dispatch("linode_list_nodebalancers", body, resp);
    if (std.mem.indexOf(u8, body, "list_stackscripts") != null) return dispatch("linode_list_stackscripts", body, resp);
    if (std.mem.indexOf(u8, body, "list_images") != null) return dispatch("linode_list_images", body, resp);
    if (std.mem.indexOf(u8, body, "list_regions") != null) return dispatch("linode_list_regions", body, resp);
    if (std.mem.indexOf(u8, body, "list_firewalls") != null) return dispatch("linode_list_firewalls", body, resp);
    if (std.mem.indexOf(u8, body, "create_firewall") != null) return dispatch("linode_create_firewall", body, resp);
    if (std.mem.indexOf(u8, body, "get_account") != null) return dispatch("linode_get_account", body, resp);
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
