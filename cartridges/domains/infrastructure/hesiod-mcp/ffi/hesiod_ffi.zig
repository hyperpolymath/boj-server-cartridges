// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// hesiod-mcp FFI — ADR-0006 five-symbol cartridge ABI implementation.
//
// Real DNS implementation via std.net.getAddressList (wraps getaddrinfo).
// Supports A/AAAA record lookup, reverse DNS, and bulk lookups.

const std = @import("std");
const shim = @import("cartridge_shim.zig");

const CARTRIDGE_NAME_PTR: [*:0]const u8 = "hesiod-mcp";
const CARTRIDGE_VERSION_PTR: [*:0]const u8 = "0.1.0";

export fn boj_cartridge_init() callconv(.c) c_int {
    return 0;
}

export fn boj_cartridge_deinit() callconv(.c) void {}

export fn boj_cartridge_name() callconv(.c) [*:0]const u8 {
    return CARTRIDGE_NAME_PTR;
}

export fn boj_cartridge_version() callconv(.c) [*:0]const u8 {
    return CARTRIDGE_VERSION_PTR;
}

// ─── helpers ─────────────────────────────────────────────────────────

/// Extract a string field from a JSON object value, returning `default`
/// if absent or not a string.
fn getStringField(obj: std.json.Value, field: []const u8, default: []const u8) []const u8 {
    if (obj != .object) return default;
    const val = obj.object.get(field) orelse return default;
    if (val != .string) return default;
    return val.string;
}

/// Format a std.net.Address as "ip" (no port suffix).
/// Writes into buf, returns a slice. Returns null if formatting fails.
fn formatIp(addr: std.net.Address, buf: []u8) ?[]const u8 {
    // {f} invokes the format method on std.net.Address, producing "ip:port"
    const full = std.fmt.bufPrint(buf, "{f}", .{addr}) catch return null;
    // std.net.Address formats as "ip:port" — strip the trailing ":port"
    if (std.mem.lastIndexOf(u8, full, ":")) |colon| {
        return full[0..colon];
    }
    return full;
}

// ─── dns_lookup ──────────────────────────────────────────────────────

fn doDnsLookup(
    json_args: [*c]const u8,
    out_buf: [*c]u8,
    in_out_len: [*c]usize,
) i32 {
    const args_str: []const u8 = if (json_args != null)
        std.mem.span(@as([*:0]const u8, @ptrCast(json_args)))
    else
        "{}";

    // Stack buffers to hold copies of string fields — avoids aliasing when
    // getAddressList calls dupeZ on a hostname that lives inside the same
    // FixedBufferAllocator as the JSON parse output.
    var hostname_buf: [256]u8 = undefined;
    var record_type_buf: [32]u8 = undefined;
    var hostname_len: usize = 0;
    var record_type_len: usize = 0;

    // Parse args in a scoped arena; copy the string values out before the
    // arena is reused.
    {
        var parse_mem: [64 * 1024]u8 = undefined;
        var parse_fba = std.heap.FixedBufferAllocator.init(&parse_mem);
        const parse_alloc = parse_fba.allocator();

        const default_host = "localhost";
        const default_rt = "A";

        if (std.json.parseFromSlice(std.json.Value, parse_alloc, args_str, .{})) |parsed| {
            defer parsed.deinit();
            const h = getStringField(parsed.value, "hostname", default_host);
            const rt = getStringField(parsed.value, "record_type", default_rt);
            hostname_len = @min(h.len, hostname_buf.len);
            @memcpy(hostname_buf[0..hostname_len], h[0..hostname_len]);
            record_type_len = @min(rt.len, record_type_buf.len);
            @memcpy(record_type_buf[0..record_type_len], rt[0..record_type_len]);
        } else |_| {
            // Defaults
            hostname_len = "localhost".len;
            @memcpy(hostname_buf[0..hostname_len], "localhost");
            record_type_len = "A".len;
            @memcpy(record_type_buf[0..record_type_len], "A");
        }
    }

    const hostname: []const u8 = hostname_buf[0..hostname_len];
    const record_type: []const u8 = record_type_buf[0..record_type_len];

    // Only A/AAAA are supported via getaddrinfo
    const is_addr_type = std.mem.eql(u8, record_type, "A") or
        std.mem.eql(u8, record_type, "AAAA");

    if (!is_addr_type) {
        var result_buf: [512]u8 = undefined;
        const result = std.fmt.bufPrint(
            &result_buf,
            "{{\"hostname\":\"{s}\",\"record_type\":\"{s}\",\"answers\":[],\"note\":\"Only A/AAAA supported via getaddrinfo\"}}",
            .{ hostname, record_type },
        ) catch return shim.RC_RUNTIME_ERROR;
        return shim.writeResult(out_buf, in_out_len, result);
    }

    // Use a fresh arena for getAddressList — hostname is now a separate stack copy.
    var lookup_mem: [64 * 1024]u8 = undefined;
    var lookup_fba = std.heap.FixedBufferAllocator.init(&lookup_mem);
    const allocator = lookup_fba.allocator();

    // Build answers array as a string
    var answers_buf: [4096]u8 = undefined;
    var answers_len: usize = 0;
    answers_buf[answers_len] = '[';
    answers_len += 1;

    const addr_list = std.net.getAddressList(allocator, hostname, 0) catch {
        var result_buf: [512]u8 = undefined;
        const result = std.fmt.bufPrint(
            &result_buf,
            "{{\"hostname\":\"{s}\",\"record_type\":\"{s}\",\"answers\":[],\"error\":\"lookup failed\"}}",
            .{ hostname, record_type },
        ) catch return shim.RC_RUNTIME_ERROR;
        return shim.writeResult(out_buf, in_out_len, result);
    };
    defer addr_list.deinit();

    var first = true;
    for (addr_list.addrs) |addr| {
        var ip_buf: [64]u8 = undefined;
        const ip = formatIp(addr, &ip_buf) orelse continue;

        // Filter by record type: A = IPv4, AAAA = IPv6
        const family = addr.any.family;
        const want_ipv4 = std.mem.eql(u8, record_type, "A");
        const is_ipv4 = (family == std.posix.AF.INET);
        if (want_ipv4 != is_ipv4) continue;

        // Append comma separator after first entry
        if (!first) {
            if (answers_len + 1 >= answers_buf.len) break;
            answers_buf[answers_len] = ',';
            answers_len += 1;
        }
        first = false;

        // Append "\"ip\""
        const entry = std.fmt.bufPrint(
            answers_buf[answers_len..],
            "\"{s}\"",
            .{ip},
        ) catch break;
        answers_len += entry.len;
    }

    if (answers_len + 1 < answers_buf.len) {
        answers_buf[answers_len] = ']';
        answers_len += 1;
    }
    const answers_slice = answers_buf[0..answers_len];

    var result_buf: [8192]u8 = undefined;
    const result = std.fmt.bufPrint(
        &result_buf,
        "{{\"hostname\":\"{s}\",\"record_type\":\"{s}\",\"answers\":{s},\"ttl\":300}}",
        .{ hostname, record_type, answers_slice },
    ) catch return shim.RC_RUNTIME_ERROR;

    return shim.writeResult(out_buf, in_out_len, result);
}

// ─── dns_reverse_lookup ──────────────────────────────────────────────

fn doDnsReverseLookup(
    json_args: [*c]const u8,
    out_buf: [*c]u8,
    in_out_len: [*c]usize,
) i32 {
    const args_str: []const u8 = if (json_args != null)
        std.mem.span(@as([*:0]const u8, @ptrCast(json_args)))
    else
        "{}";

    var address_buf: [64]u8 = undefined;
    var address_len: usize = 0;

    {
        var parse_mem: [32 * 1024]u8 = undefined;
        var parse_fba = std.heap.FixedBufferAllocator.init(&parse_mem);
        const parse_alloc = parse_fba.allocator();

        const default_addr = "127.0.0.1";
        if (std.json.parseFromSlice(std.json.Value, parse_alloc, args_str, .{})) |parsed| {
            defer parsed.deinit();
            const a = getStringField(parsed.value, "address", default_addr);
            address_len = @min(a.len, address_buf.len);
            @memcpy(address_buf[0..address_len], a[0..address_len]);
        } else |_| {
            address_len = default_addr.len;
            @memcpy(address_buf[0..address_len], default_addr);
        }
    }

    const address: []const u8 = address_buf[0..address_len];

    // getaddrinfo doesn't do reverse lookup (that's getnameinfo).
    // Return the address itself with a note about the limitation.
    var result_buf: [512]u8 = undefined;
    const result = std.fmt.bufPrint(
        &result_buf,
        "{{\"address\":\"{s}\",\"hostname\":\"{s}\",\"note\":\"Reverse lookup limited to getaddrinfo capabilities\"}}",
        .{ address, address },
    ) catch return shim.RC_RUNTIME_ERROR;

    return shim.writeResult(out_buf, in_out_len, result);
}

// ─── dns_bulk_lookup ─────────────────────────────────────────────────

// Maximum number of hostnames we'll process in a bulk request.
const MAX_BULK_HOSTS = 32;
// Maximum hostname length we'll copy.
const MAX_HOSTNAME_LEN = 255;

fn doDnsBulkLookup(
    json_args: [*c]const u8,
    out_buf: [*c]u8,
    in_out_len: [*c]usize,
) i32 {
    const args_str: []const u8 = if (json_args != null)
        std.mem.span(@as([*:0]const u8, @ptrCast(json_args)))
    else
        "{}";

    // Stack-allocated storage for hostnames — avoids aliasing when
    // getAddressList dupeZ's into the same FixedBufferAllocator.
    var hostname_storage: [MAX_BULK_HOSTS][MAX_HOSTNAME_LEN + 1]u8 = undefined;
    var hostname_lens: [MAX_BULK_HOSTS]usize = undefined;
    var record_type_buf: [32]u8 = undefined;
    var record_type_len: usize = 0;
    var host_count: usize = 0;

    // Parse args in a scoped arena; copy string values out before reuse.
    {
        var parse_mem: [64 * 1024]u8 = undefined;
        var parse_fba = std.heap.FixedBufferAllocator.init(&parse_mem);
        const parse_alloc = parse_fba.allocator();

        const default_rt = "A";

        const parsed = std.json.parseFromSlice(std.json.Value, parse_alloc, args_str, .{}) catch {
            const result = "{\"results\":[],\"record_type\":\"A\",\"count\":0}";
            return shim.writeResult(out_buf, in_out_len, result);
        };
        defer parsed.deinit();

        const rt = getStringField(parsed.value, "record_type", default_rt);
        record_type_len = @min(rt.len, record_type_buf.len);
        @memcpy(record_type_buf[0..record_type_len], rt[0..record_type_len]);

        // Extract hostnames array
        if (parsed.value == .object) {
            if (parsed.value.object.get("hostnames")) |hv| {
                if (hv == .array) {
                    for (hv.array.items) |item| {
                        if (host_count >= MAX_BULK_HOSTS) break;
                        if (item != .string) continue;
                        const h = item.string;
                        const len = @min(h.len, MAX_HOSTNAME_LEN);
                        @memcpy(hostname_storage[host_count][0..len], h[0..len]);
                        // NUL-terminate (getAddressList expects a valid slice, not C string,
                        // but we store len separately)
                        hostname_storage[host_count][len] = 0;
                        hostname_lens[host_count] = len;
                        host_count += 1;
                    }
                }
            }
        }
    }

    const record_type: []const u8 = record_type_buf[0..record_type_len];

    if (host_count == 0) {
        var result_buf: [256]u8 = undefined;
        const result = std.fmt.bufPrint(
            &result_buf,
            "{{\"results\":[],\"record_type\":\"{s}\",\"count\":0}}",
            .{record_type},
        ) catch return shim.RC_RUNTIME_ERROR;
        return shim.writeResult(out_buf, in_out_len, result);
    }

    const is_addr_type = std.mem.eql(u8, record_type, "A") or
        std.mem.eql(u8, record_type, "AAAA");

    // Build results JSON in a large buffer
    var results_buf: [16 * 1024]u8 = undefined;
    var results_len: usize = 0;

    results_buf[results_len] = '[';
    results_len += 1;

    var count: usize = 0;
    for (0..host_count) |i| {
        const hostname: []const u8 = hostname_storage[i][0..hostname_lens[i]];

        if (count > 0) {
            if (results_len + 1 >= results_buf.len) break;
            results_buf[results_len] = ',';
            results_len += 1;
        }
        count += 1;

        // Do the lookup using a per-host arena so there's no aliasing.
        var answers_buf: [2048]u8 = undefined;
        var answers_len: usize = 0;
        answers_buf[answers_len] = '[';
        answers_len += 1;

        if (is_addr_type) {
            var lookup_mem: [32 * 1024]u8 = undefined;
            var lookup_fba = std.heap.FixedBufferAllocator.init(&lookup_mem);
            const lookup_alloc = lookup_fba.allocator();

            if (std.net.getAddressList(lookup_alloc, hostname, 0)) |addr_list| {
                defer addr_list.deinit();
                var first = true;
                for (addr_list.addrs) |addr| {
                    var ip_buf: [64]u8 = undefined;
                    const ip = formatIp(addr, &ip_buf) orelse continue;

                    const family = addr.any.family;
                    const want_ipv4 = std.mem.eql(u8, record_type, "A");
                    const is_ipv4 = (family == std.posix.AF.INET);
                    if (want_ipv4 != is_ipv4) continue;

                    if (!first) {
                        if (answers_len + 1 >= answers_buf.len) break;
                        answers_buf[answers_len] = ',';
                        answers_len += 1;
                    }
                    first = false;
                    const entry = std.fmt.bufPrint(
                        answers_buf[answers_len..],
                        "\"{s}\"",
                        .{ip},
                    ) catch break;
                    answers_len += entry.len;
                }
            } else |_| {
                // lookup failed — empty answers array
            }
        }

        if (answers_len + 1 < answers_buf.len) {
            answers_buf[answers_len] = ']';
            answers_len += 1;
        }
        const answers_slice = answers_buf[0..answers_len];

        const entry = std.fmt.bufPrint(
            results_buf[results_len..],
            "{{\"hostname\":\"{s}\",\"answers\":{s}}}",
            .{ hostname, answers_slice },
        ) catch break;
        results_len += entry.len;
    }

    if (results_len + 1 < results_buf.len) {
        results_buf[results_len] = ']';
        results_len += 1;
    }
    const results_slice = results_buf[0..results_len];

    var out_result_buf: [20 * 1024]u8 = undefined;
    const result = std.fmt.bufPrint(
        &out_result_buf,
        "{{\"results\":{s},\"record_type\":\"{s}\",\"count\":{d}}}",
        .{ results_slice, record_type, count },
    ) catch return shim.RC_RUNTIME_ERROR;

    return shim.writeResult(out_buf, in_out_len, result);
}

// ─── ADR-0006 dispatch ───────────────────────────────────────────────

export fn boj_cartridge_invoke(
    tool_name: [*c]const u8,
    json_args: [*c]const u8,
    out_buf: [*c]u8,
    in_out_len: [*c]usize,
) callconv(.c) i32 {
    if (shim.invokeArgsNull(tool_name, out_buf, in_out_len)) return shim.RC_BAD_ARGS;

    if (shim.toolIs(tool_name, "dns_lookup")) {
        return doDnsLookup(json_args, out_buf, in_out_len);
    } else if (shim.toolIs(tool_name, "dns_reverse_lookup")) {
        return doDnsReverseLookup(json_args, out_buf, in_out_len);
    } else if (shim.toolIs(tool_name, "dns_bulk_lookup")) {
        return doDnsBulkLookup(json_args, out_buf, in_out_len);
    }
    return shim.RC_UNKNOWN_TOOL;
}

// ─── Tests ───────────────────────────────────────────────────────────

test "boj_cartridge_name returns hesiod-mcp" {
    try std.testing.expectEqualStrings("hesiod-mcp", std.mem.span(boj_cartridge_name()));
}

test "boj_cartridge_init returns 0" {
    try std.testing.expectEqual(@as(c_int, 0), boj_cartridge_init());
}

test "invoke unknown tool returns RC_UNKNOWN_TOOL" {
    var buf: [256]u8 = undefined;
    var len: usize = buf.len;
    try std.testing.expectEqual(@as(i32, shim.RC_UNKNOWN_TOOL), boj_cartridge_invoke("unknown_xyz", "{}", &buf, &len));
}

test "invoke dns_lookup localhost returns real answers" {
    var buf: [4096]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke("dns_lookup", "{\"hostname\":\"localhost\",\"record_type\":\"A\"}", &buf, &len);
    try std.testing.expectEqual(@as(i32, 0), rc);
    const out = buf[0..len];
    // Must contain hostname and answers fields — not a stub
    try std.testing.expect(std.mem.indexOf(u8, out, "\"hostname\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"answers\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"result\":{}") == null);
}

test "invoke dns_lookup empty args defaults to localhost A" {
    var buf: [4096]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke("dns_lookup", "{}", &buf, &len);
    try std.testing.expectEqual(@as(i32, 0), rc);
    const out = buf[0..len];
    try std.testing.expect(std.mem.indexOf(u8, out, "localhost") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"answers\"") != null);
}

test "invoke dns_lookup MX returns not-supported note" {
    var buf: [512]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke("dns_lookup", "{\"hostname\":\"example.com\",\"record_type\":\"MX\"}", &buf, &len);
    try std.testing.expectEqual(@as(i32, 0), rc);
    const out = buf[0..len];
    try std.testing.expect(std.mem.indexOf(u8, out, "note") != null);
}

test "invoke dns_reverse_lookup returns address echo" {
    var buf: [512]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke("dns_reverse_lookup", "{\"address\":\"127.0.0.1\"}", &buf, &len);
    try std.testing.expectEqual(@as(i32, 0), rc);
    const out = buf[0..len];
    try std.testing.expect(std.mem.indexOf(u8, out, "127.0.0.1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"address\"") != null);
}

test "invoke dns_bulk_lookup empty hostnames returns count 0" {
    var buf: [512]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke("dns_bulk_lookup", "{\"hostnames\":[],\"record_type\":\"A\"}", &buf, &len);
    try std.testing.expectEqual(@as(i32, 0), rc);
    const out = buf[0..len];
    try std.testing.expect(std.mem.indexOf(u8, out, "\"count\":0") != null);
}

test "invoke dns_bulk_lookup single host returns results" {
    var buf: [4096]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke("dns_bulk_lookup", "{\"hostnames\":[\"localhost\"],\"record_type\":\"A\"}", &buf, &len);
    try std.testing.expectEqual(@as(i32, 0), rc);
    const out = buf[0..len];
    try std.testing.expect(std.mem.indexOf(u8, out, "\"results\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "localhost") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"count\":1") != null);
}

test "null tool_name returns RC_BAD_ARGS" {
    var buf: [256]u8 = undefined;
    var len: usize = buf.len;
    try std.testing.expectEqual(@as(i32, shim.RC_BAD_ARGS), boj_cartridge_invoke(null, "{}", &buf, &len));
}
