// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// gossamer-mcp/adapter/gossamer_adapter.zig
//
// TEMPLATE adapter — `just mint` copies this tree, so this file is the
// shape every new cartridge inherits. Keep it canonical.
//
// INTERNAL-ONLY unified adapter. This is NOT a public ingress. Per
// ADR-0004 the only governed public surface is the http-capability-gateway
// (tier-2) in front of the unified Zig core; cartridge adapters bind
// loopback and sit behind it. One listener, one port, protocol-routed
// (REST + SSE + GraphQL + gRPC-compat) into a SINGLE transaction-gated
// dispatch → the one Zig ABI (ffi.boj_cartridge_invoke). Deliberately NOT
// N parallel servers and NOT a public listener.
//
//   POST /invoke            → REST            (JSON in/out)
//   POST /sse               → SSE             (text/event-stream)
//   POST /graphql           → GraphQL         (op parsed from body)
//   POST /grpc/<Svc>/<Mthd> → gRPC-compat     (tool = method)
//
// Every request passes the transaction gate (exposureGate) BEFORE dispatch.
// No request reaches the ABI ungated — this boundary is not a
// gatekeeperless gateway (estate interface-safety policy).
//
// Gossamer webview window manager. Creates and manages native desktop
// windows with panel loading and JavaScript evaluation.
// Tools: gossamer_create_window, gossamer_load_panel, gossamer_eval_js,
//        gossamer_get_version

const std = @import("std");
const ffi = @import("gossamer_ffi");

// The process-wide `std.Io` lives on the shared ADR-0006 shim, re-exported
// by the FFI module so the adapter and the cartridge behind it use ONE
// runtime rather than two. Zig 0.16 moved the sockets API onto `std.Io`.
const shim = ffi.shim;
const net = std.Io.net;

// Loopback-only by construction: this adapter is internal, fronted by the
// http-capability-gateway (ADR-0004). Never bind a routable interface.
const BIND_IP = [4]u8{ 127, 0, 0, 1 };
const PORT: u16 = 9109;

const REQ_BUF_LEN: usize = 8 * 1024;
const OUT_BUF_LEN: usize = 4 * 1024;

// ── Transaction gate (ADR-0004 exposure ladder) ─────────────────────────
//
// Encoding matches the estate Idris2 exposure contracts
// (e.g. K9iserMcp.SafeK9iser): 0=Public 1=Authenticated 2=Internal.
const Exposure = enum(u8) { public = 0, authenticated = 1, internal = 2 };

// gossamer-mcp cartridge.json: auth.method = "none" → requiredExposure = Public.
const REQUIRED_EXPOSURE: Exposure = .public;

/// Zig mirror of the estate `exposureSatisfied` contract, cross-checked by
/// the truth-table test below.
fn exposureSatisfied(required: Exposure, presented: Exposure, is_local: bool) bool {
    if (is_local) return true; // loopback callers are locally trusted
    return switch (required) {
        .public => true,
        .authenticated => presented == .authenticated or presented == .internal,
        .internal => presented == .internal,
    };
}

/// Parse the `X-Trust-Level` request header the gateway/sidecar sets.
/// Missing/unknown → Public (conservative). Case-insensitive header name.
fn presentedExposure(req: []const u8) Exposure {
    const val = headerValue(req, "x-trust-level") orelse return .public;
    if (eqIgnoreCase(val, "internal")) return .internal;
    if (eqIgnoreCase(val, "authenticated")) return .authenticated;
    return .public;
}

fn eqIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| if (std.ascii.toLower(x) != std.ascii.toLower(y)) return false;
    return true;
}

/// Case-insensitive single-header lookup over a raw HTTP/1.1 request.
fn headerValue(req: []const u8, name: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, req, '\n');
    _ = lines.next(); // request line
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, "\r");
        if (line.len == 0) break; // end of headers
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        if (eqIgnoreCase(std.mem.trim(u8, line[0..colon], " "), name))
            return std.mem.trim(u8, line[colon + 1 ..], " ");
    }
    return null;
}

const Dispatch = struct { status: u16, body: []const u8 };

/// The single point where every protocol converges onto the one Zig ABI.
/// Response passthrough: whatever the FFI writes goes back to the wire
/// unmodified.
fn dispatch(tool: []const u8, args_json: []const u8, out: []u8) Dispatch {
    var tnbuf: [128]u8 = undefined;
    if (tool.len == 0 or tool.len >= tnbuf.len)
        return .{ .status = 400, .body = "{\"error\":\"bad-tool\"}" };
    @memcpy(tnbuf[0..tool.len], tool);
    tnbuf[tool.len] = 0;

    var abuf: [4096]u8 = undefined;
    const a = if (args_json.len == 0) "{}" else args_json;
    if (a.len >= abuf.len)
        return .{ .status = 413, .body = "{\"error\":\"args-too-large\"}" };
    @memcpy(abuf[0..a.len], a);
    abuf[a.len] = 0;

    var len: usize = out.len;
    const rc = ffi.boj_cartridge_invoke(@ptrCast(&tnbuf), @ptrCast(&abuf), @ptrCast(out.ptr), &len);
    return switch (rc) {
        0 => .{ .status = 200, .body = out[0..len] },
        -1 => .{ .status = 404, .body = "{\"error\":\"unknown-tool\"}" },
        -2 => .{ .status = 400, .body = "{\"error\":\"bad-args\"}" },
        -3 => .{ .status = 500, .body = "{\"error\":\"buffer-too-small\"}" },
        else => .{ .status = 500, .body = "{\"error\":\"invoke-failed\"}" },
    };
}

const Protocol = enum { rest, sse, graphql, grpc, unknown };

fn classify(path: []const u8) Protocol {
    if (std.mem.startsWith(u8, path, "/invoke")) return .rest;
    if (std.mem.startsWith(u8, path, "/sse")) return .sse;
    if (std.mem.startsWith(u8, path, "/graphql")) return .graphql;
    if (std.mem.startsWith(u8, path, "/grpc/")) return .grpc;
    return .unknown;
}

/// The tool catalogue. `cartridge.json` is the source of truth; drift
/// between this list and the manifest is a CI failure.
const TOOLS = [_][]const u8{
    "gossamer_create_window",
    "gossamer_load_panel",
    "gossamer_eval_js",
    "gossamer_get_version",
};

fn toolFor(proto: Protocol, path: []const u8, body: []const u8) ?[]const u8 {
    switch (proto) {
        .grpc => {
            var it = std.mem.splitScalar(u8, path, '/');
            _ = it.next(); // ""
            _ = it.next(); // "grpc"
            _ = it.next(); // service
            return it.next();
        },
        .rest, .sse => {
            if (std.mem.indexOf(u8, path, "tool=")) |q| {
                const rest = path[q + 5 ..];
                const end = std.mem.indexOfAny(u8, rest, "& ") orelse rest.len;
                if (end > 0) return rest[0..end];
            }
            return jsonStringField(body, "tool");
        },
        .graphql => {
            for (TOOLS) |t| if (std.mem.indexOf(u8, body, t) != null) return t;
            return null;
        },
        .unknown => return null,
    }
}

fn jsonStringField(body: []const u8, key: []const u8) ?[]const u8 {
    var kbuf: [64]u8 = undefined;
    if (key.len + 2 >= kbuf.len) return null;
    kbuf[0] = '"';
    @memcpy(kbuf[1 .. 1 + key.len], key);
    kbuf[1 + key.len] = '"';
    const needle = kbuf[0 .. key.len + 2];
    const k = std.mem.indexOf(u8, body, needle) orelse return null;
    var i = k + needle.len;
    while (i < body.len and (body[i] == ':' or body[i] == ' ')) : (i += 1) {}
    if (i >= body.len or body[i] != '"') return null;
    i += 1;
    const start = i;
    while (i < body.len and body[i] != '"') : (i += 1) {}
    if (i > start) return body[start..i] else return null;
}

// ── Wire I/O (Zig 0.16 std.Io.net) ──────────────────────────────────────

fn writeHttp(io: std.Io, stream: net.Stream, status: u16, ctype: []const u8, body: []const u8) void {
    var wbuf: [1024]u8 = undefined;
    var sw = stream.writer(io, &wbuf);
    const w = &sw.interface;
    w.print(
        "HTTP/1.1 {d} OK\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
        .{ status, ctype, body.len },
    ) catch return;
    w.writeAll(body) catch return;
    w.flush() catch return;
}

fn writeSse(io: std.Io, stream: net.Stream, d: Dispatch) void {
    var wbuf: [1024]u8 = undefined;
    var sw = stream.writer(io, &wbuf);
    const w = &sw.interface;
    w.writeAll("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n") catch return;
    w.writeAll("event: open\ndata: {\"cartridge\":\"gossamer-mcp\"}\n\n") catch return;
    const ev = if (d.status == 200) "result" else "error";
    w.print("event: {s}\ndata: {s}\n\n", .{ ev, d.body }) catch return;
    w.writeAll("event: done\ndata: {}\n\n") catch return;
    w.flush() catch return;
}

// Loopback-only listener ⇒ peers are local by construction. We still
// evaluate the gate every request (no gatekeeperless path); the
// non-local branch is exercised by exposureSatisfied's tests.
fn handleConnection(io: std.Io, stream: net.Stream) void {
    defer stream.close(io);

    var rbuf: [REQ_BUF_LEN]u8 = undefined;
    var sr = stream.reader(io, &rbuf);
    sr.interface.fillMore() catch return;
    const req = sr.interface.buffered();

    var lines = std.mem.splitScalar(u8, req, '\n');
    const first = lines.next() orelse return;
    var parts = std.mem.splitScalar(u8, std.mem.trim(u8, first, "\r"), ' ');
    _ = parts.next(); // method
    const path = parts.next() orelse return;

    const body_start = std.mem.indexOf(u8, req, "\r\n\r\n");
    const body = if (body_start) |bs| req[bs + 4 ..] else "";

    const proto = classify(path);
    if (proto == .unknown) {
        writeHttp(io, stream, 404, "application/json", "{\"error\":\"route-not-found\"}");
        return;
    }

    // ── TRANSACTION GATE — runs before dispatch, every request ──────────
    const is_local = true; // loopback-bound (BIND_IP); see module header
    if (!exposureSatisfied(REQUIRED_EXPOSURE, presentedExposure(req), is_local)) {
        writeHttp(io, stream, 403, "application/json", "{\"error\":\"forbidden\",\"detail\":\"exposure-gate\"}");
        return;
    }

    const tool = toolFor(proto, path, body) orelse {
        writeHttp(io, stream, 400, "application/json", "{\"error\":\"missing-tool\"}");
        return;
    };

    var out: [OUT_BUF_LEN]u8 = undefined;
    const d = dispatch(tool, body, &out);

    switch (proto) {
        .sse => writeSse(io, stream, d),
        .graphql => {
            var gb: [OUT_BUF_LEN + 256]u8 = undefined;
            const g = std.fmt.bufPrint(&gb, "{{\"data\":{{\"invoke\":{s}}}}}", .{d.body}) catch d.body;
            writeHttp(io, stream, d.status, "application/json", g);
        },
        else => writeHttp(io, stream, d.status, "application/json", d.body), // rest, grpc
    }
}

pub fn main() !void {
    _ = ffi.boj_cartridge_init();
    defer ffi.boj_cartridge_deinit();

    const io = shim.io();
    const addr: net.IpAddress = .{ .ip4 = .{ .bytes = BIND_IP, .port = PORT } };
    var server = try addr.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);

    std.debug.print("gossamer-mcp INTERNAL unified adapter on 127.0.0.1:{d} (behind http-capability-gateway; rest|sse|graphql|grpc; transaction-gated)\n", .{PORT});
    while (true) {
        const stream = try server.accept(io);
        const t = try std.Thread.spawn(.{}, handleConnection, .{ io, stream });
        t.detach();
    }
}

// ───────────────────────── tests ─────────────────────────

test "classify routes each protocol to one surface" {
    try std.testing.expectEqual(Protocol.rest, classify("/invoke"));
    try std.testing.expectEqual(Protocol.sse, classify("/sse"));
    try std.testing.expectEqual(Protocol.graphql, classify("/graphql"));
    try std.testing.expectEqual(Protocol.grpc, classify("/grpc/Gossamer/gossamer_eval_js"));
    try std.testing.expectEqual(Protocol.unknown, classify("/nope"));
}

test "toolFor extracts across protocols" {
    try std.testing.expectEqualStrings("gossamer_eval_js", toolFor(.grpc, "/grpc/Gossamer/gossamer_eval_js", "").?);
    try std.testing.expectEqualStrings("gossamer_load_panel", toolFor(.rest, "/invoke?tool=gossamer_load_panel", "").?);
    try std.testing.expectEqualStrings("gossamer_get_version", toolFor(.sse, "/sse", "{\"tool\":\"gossamer_get_version\"}").?);
    try std.testing.expectEqualStrings("gossamer_create_window", toolFor(.graphql, "/graphql", "{query: invoke(tool:\"gossamer_create_window\")}").?);
    try std.testing.expect(toolFor(.rest, "/invoke", "{}") == null);
}

test "dispatch funnels every declared tool into the one Zig ABI" {
    var out: [OUT_BUF_LEN]u8 = undefined;
    for (TOOLS) |t| {
        const d = dispatch(t, "{}", &out);
        try std.testing.expectEqual(@as(u16, 200), d.status);
        try std.testing.expect(std.mem.indexOf(u8, d.body, "result") != null);
    }
    try std.testing.expectEqual(@as(u16, 404), dispatch("nope", "{}", &out).status);
    try std.testing.expectEqual(@as(u16, 400), dispatch("", "{}", &out).status);
}

// Transaction-gate truth table — must match the estate Idris2
// `exposureSatisfied` contract exactly.
test "exposureSatisfied mirrors the Idris2 contract" {
    // local caller: always permitted regardless of required/presented
    try std.testing.expect(exposureSatisfied(.internal, .public, true));
    // public requirement: any presented level passes
    try std.testing.expect(exposureSatisfied(.public, .public, false));
    // authenticated requirement
    try std.testing.expect(!exposureSatisfied(.authenticated, .public, false));
    try std.testing.expect(exposureSatisfied(.authenticated, .authenticated, false));
    try std.testing.expect(exposureSatisfied(.authenticated, .internal, false));
    // internal requirement
    try std.testing.expect(!exposureSatisfied(.internal, .authenticated, false));
    try std.testing.expect(exposureSatisfied(.internal, .internal, false));
}

test "presentedExposure parses X-Trust-Level (case-insensitive)" {
    const req = "POST /invoke HTTP/1.1\r\nHost: x\r\nX-Trust-Level: Internal\r\n\r\n{}";
    try std.testing.expectEqual(Exposure.internal, presentedExposure(req));
    try std.testing.expectEqual(Exposure.public, presentedExposure("POST / HTTP/1.1\r\n\r\n"));
}
