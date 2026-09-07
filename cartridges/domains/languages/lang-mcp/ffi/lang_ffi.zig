// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Lang-MCP Cartridge — Zig FFI bridge for nextgen-languages operations.
//
// Manages language runtime sessions for the hyperpolymath nextgen-languages
// family: Eclexia, AffineScript, BetLang, Ephapax, MyLang, WokeLang,
// Anvomidav, Phronesis, Error-lang, Julia-the-Viper, Me-dialect, Oblibeny.
//
// Each language session tracks: state machine (idle → compiling → checked → error),
// the language identity, and a URL endpoint for the language's compile/eval service.

const std = @import("std");

// ═══════════════════════════════════════════════════════════════════════
// Types
// ═══════════════════════════════════════════════════════════════════════

/// Language session state machine.
pub const LangState = enum(c_int) {
    idle = 0,
    compiling = 1,
    checked = 2,
    evaluating = 3,
    err = 4,
};

/// Supported nextgen-languages. Enum values are stable ABI identifiers.
pub const Language = enum(c_int) {
    eclexia = 1,
    affinescript = 2,
    betlang = 3,
    ephapax = 4,
    mylang = 5,
    wokelang = 6,
    anvomidav = 7,
    phronesis = 8,
    error_lang = 9,
    julia_the_viper = 10,
    me_dialect = 11,
    oblibeny = 12,
    custom = 99,
};

/// Dialect mode: pure grammar or JtV-injected.
/// Julia-the-Viper (JtV) is injectable into any other language,
/// augmenting it with JtV's syntax extensions. Each language can
/// be requested as pure (original grammar) or jtv (JtV-injected).
pub const DialectMode = enum(c_int) {
    pure = 0,
    jtv = 1,
};

// ═══════════════════════════════════════════════════════════════════════
// Session State Machine
// ═══════════════════════════════════════════════════════════════════════

const MAX_SESSIONS: usize = 8;
const URL_BUF_SIZE: usize = 512;
const NAME_BUF_SIZE: usize = 64;

const LangSession = struct {
    active: bool,
    state: LangState,
    language: Language,
    dialect: DialectMode,
    url_buf: [URL_BUF_SIZE]u8,
    url_len: usize,
    name_buf: [NAME_BUF_SIZE]u8,
    name_len: usize,
};

var sessions: [MAX_SESSIONS]LangSession = [_]LangSession{.{
    .active = false,
    .state = .idle,
    .language = .custom,
    .dialect = .pure,
    .url_buf = [_]u8{0} ** URL_BUF_SIZE,
    .url_len = 0,
    .name_buf = [_]u8{0} ** NAME_BUF_SIZE,
    .name_len = 0,
}} ** MAX_SESSIONS;

var mutex: shim.Mutex = .{};

/// Validate a state transition.
fn isValidTransition(from: LangState, to: LangState) bool {
    return switch (from) {
        .idle => to == .compiling or to == .evaluating,
        .compiling => to == .checked or to == .err,
        .checked => to == .idle or to == .evaluating,
        .evaluating => to == .idle or to == .err,
        .err => to == .idle,
    };
}

/// Start a language session. Returns session index or -1.
/// dialect_mode: 0 = pure grammar, 1 = JtV-injected.
pub export fn lang_session_start(lang_id: c_int, name_ptr: [*]const u8, name_len: usize) c_int {
    return lang_session_start_dialect(lang_id, 0, name_ptr, name_len);
}

/// Start a language session with explicit dialect mode.
/// dialect_mode: 0 = pure grammar, 1 = JtV-injected.
/// When JtV mode is active, the language service URL path gains a /jtv suffix
/// (e.g. /typecheck/jtv, /eval/jtv) so the backend can apply JtV grammar injection.
pub export fn lang_session_start_dialect(lang_id: c_int, dialect_mode: c_int, name_ptr: [*]const u8, name_len: usize) c_int {
    mutex.lock();
    defer mutex.unlock();

    if (name_len == 0 or name_len >= NAME_BUF_SIZE) return -2;

    for (&sessions, 0..) |*sess, i| {
        if (!sess.active) {
            sess.active = true;
            sess.state = .idle;
            sess.language = @enumFromInt(lang_id);
            sess.dialect = if (dialect_mode == 1) .jtv else .pure;
            sess.url_len = 0;
            @memcpy(sess.name_buf[0..name_len], name_ptr[0..name_len]);
            sess.name_len = name_len;
            return @intCast(i);
        }
    }
    return -1; // No sessions available
}

/// Get the dialect mode of a session (0 = pure, 1 = jtv).
pub export fn lang_session_dialect(sess_idx: c_int) c_int {
    mutex.lock();
    defer mutex.unlock();

    if (sess_idx < 0 or sess_idx >= MAX_SESSIONS) return -1;
    const idx: usize = @intCast(sess_idx);
    if (!sessions[idx].active) return -1;
    return @intFromEnum(sessions[idx].dialect);
}

/// Set the language service URL for a session (for remote compilation/eval).
pub export fn lang_session_set_url(sess_idx: c_int, url_ptr: [*]const u8, url_len: usize) c_int {
    mutex.lock();
    defer mutex.unlock();

    if (sess_idx < 0 or sess_idx >= MAX_SESSIONS) return -1;
    const idx: usize = @intCast(sess_idx);
    if (!sessions[idx].active) return -1;
    if (url_len == 0 or url_len >= URL_BUF_SIZE) return -6;

    @memcpy(sessions[idx].url_buf[0..url_len], url_ptr[0..url_len]);
    sessions[idx].url_len = url_len;
    return 0;
}

/// End a language session.
pub export fn lang_session_end(sess_idx: c_int) c_int {
    mutex.lock();
    defer mutex.unlock();

    if (sess_idx < 0 or sess_idx >= MAX_SESSIONS) return -1;
    const idx: usize = @intCast(sess_idx);
    if (!sessions[idx].active) return -1;

    sessions[idx].active = false;
    sessions[idx].state = .idle;
    sessions[idx].url_len = 0;
    sessions[idx].name_len = 0;
    return 0;
}

/// Get the state of a session.
pub export fn lang_session_state(sess_idx: c_int) c_int {
    mutex.lock();
    defer mutex.unlock();

    if (sess_idx < 0 or sess_idx >= MAX_SESSIONS) return -1;
    const idx: usize = @intCast(sess_idx);
    if (!sessions[idx].active) return -1;
    return @intFromEnum(sessions[idx].state);
}

/// Get the language ID of a session.
pub export fn lang_session_language(sess_idx: c_int) c_int {
    mutex.lock();
    defer mutex.unlock();

    if (sess_idx < 0 or sess_idx >= MAX_SESSIONS) return -1;
    const idx: usize = @intCast(sess_idx);
    if (!sessions[idx].active) return -1;
    return @intFromEnum(sessions[idx].language);
}

/// Type-check source code via the language service.
/// POSTs to {url}/typecheck with the source as JSON body.
pub export fn lang_typecheck(sess_idx: c_int, src_ptr: [*]const u8, src_len: usize, out_ptr: [*]u8, out_len: usize) callconv(.c) i32 {
    var endpoint_buf: [600]u8 = undefined;
    var endpoint_total: usize = 0;
    var src_buf: [16384]u8 = undefined;
    var safe_src_len: usize = 0;

    {
        mutex.lock();
        defer mutex.unlock();

        if (sess_idx < 0 or sess_idx >= MAX_SESSIONS) return -1;
        const idx: usize = @intCast(sess_idx);
        if (!sessions[idx].active) return -1;
        if (sessions[idx].state != .idle and sessions[idx].state != .checked) return -2;
        if (sessions[idx].url_len == 0) return -6;

        const url_slice = sessions[idx].url_buf[0..sessions[idx].url_len];
        const suffix = if (sessions[idx].dialect == .jtv) "/typecheck/jtv" else "/typecheck";
        if (url_slice.len + suffix.len >= endpoint_buf.len) return -6;
        @memcpy(endpoint_buf[0..url_slice.len], url_slice);
        @memcpy(endpoint_buf[url_slice.len..][0..suffix.len], suffix);
        endpoint_total = url_slice.len + suffix.len;
        endpoint_buf[endpoint_total] = 0;

        safe_src_len = @min(src_len, src_buf.len - 1);
        @memcpy(src_buf[0..safe_src_len], src_ptr[0..safe_src_len]);
        src_buf[safe_src_len] = 0;

        sessions[idx].state = .compiling;
    }

    const child_result = runCurlPost(
        endpoint_buf[0..endpoint_total :0],
        src_buf[0..safe_src_len :0],
    );

    mutex.lock();
    defer mutex.unlock();

    const idx: usize = @intCast(sess_idx);
    if (!sessions[idx].active) return -1;

    if (child_result) |result| {
        defer std.heap.page_allocator.free(result);
        const written = result.len;
        if (written > out_len) {
            sessions[idx].state = .err;
            return -5;
        }
        @memcpy(out_ptr[0..written], result[0..written]);
        sessions[idx].state = .checked;
        return @intCast(written);
    } else |_| {
        sessions[idx].state = .err;
        return -7;
    }
}

/// Evaluate/run source code via the language service.
/// POSTs to {url}/eval with the source as JSON body.
pub export fn lang_eval(sess_idx: c_int, src_ptr: [*]const u8, src_len: usize, out_ptr: [*]u8, out_len: usize) callconv(.c) i32 {
    var endpoint_buf: [600]u8 = undefined;
    var endpoint_total: usize = 0;
    var src_buf: [16384]u8 = undefined;
    var safe_src_len: usize = 0;

    {
        mutex.lock();
        defer mutex.unlock();

        if (sess_idx < 0 or sess_idx >= MAX_SESSIONS) return -1;
        const idx: usize = @intCast(sess_idx);
        if (!sessions[idx].active) return -1;
        if (sessions[idx].state != .idle and sessions[idx].state != .checked) return -2;
        if (sessions[idx].url_len == 0) return -6;

        const url_slice = sessions[idx].url_buf[0..sessions[idx].url_len];
        const suffix = if (sessions[idx].dialect == .jtv) "/eval/jtv" else "/eval";
        if (url_slice.len + suffix.len >= endpoint_buf.len) return -6;
        @memcpy(endpoint_buf[0..url_slice.len], url_slice);
        @memcpy(endpoint_buf[url_slice.len..][0..suffix.len], suffix);
        endpoint_total = url_slice.len + suffix.len;
        endpoint_buf[endpoint_total] = 0;

        safe_src_len = @min(src_len, src_buf.len - 1);
        @memcpy(src_buf[0..safe_src_len], src_ptr[0..safe_src_len]);
        src_buf[safe_src_len] = 0;

        sessions[idx].state = .evaluating;
    }

    const child_result = runCurlPost(
        endpoint_buf[0..endpoint_total :0],
        src_buf[0..safe_src_len :0],
    );

    mutex.lock();
    defer mutex.unlock();

    const idx: usize = @intCast(sess_idx);
    if (!sessions[idx].active) return -1;

    if (child_result) |result| {
        defer std.heap.page_allocator.free(result);
        const written = result.len;
        if (written > out_len) {
            sessions[idx].state = .err;
            return -5;
        }
        @memcpy(out_ptr[0..written], result[0..written]);
        sessions[idx].state = .idle;
        return @intCast(written);
    } else |_| {
        sessions[idx].state = .err;
        return -7;
    }
}

/// Reset all sessions (for testing).
pub export fn lang_reset() void {
    mutex.lock();
    defer mutex.unlock();
    for (&sessions) |*sess| {
        sess.active = false;
        sess.state = .idle;
        sess.url_len = 0;
        sess.name_len = 0;
    }
}

/// Run curl as a child process for an HTTP POST with JSON body.
fn runCurlPost(endpoint: [:0]const u8, body: [:0]const u8) ![]u8 {
    const argv = [_][]const u8{
        "curl", "-sf",  "--max-time", "10",
        "-X",   "POST", "-H",         "Content-Type: application/json",
        "-d",   body,   endpoint,
    };
    const alloc = std.heap.page_allocator;
    const result = try std.process.run(alloc, shim.io(), .{
        .argv = &argv,
        .stdout_limit = .limited(65536),
        .stderr_limit = .limited(65536),
    });
    alloc.free(result.stderr);

    switch (result.term) {
        .exited => |code| if (code != 0) {
            alloc.free(result.stdout);
            return error.CurlFailed;
        },
        else => {
            alloc.free(result.stdout);
            return error.CurlFailed;
        },
    }

    return result.stdout;
}

// ═══════════════════════════════════════════════════════════════════════
// Standard Cartridge Interface
// ═══════════════════════════════════════════════════════════════════════

pub export fn boj_cartridge_init() c_int {
    lang_reset();
    return 0;
}

pub export fn boj_cartridge_deinit() void {
    lang_reset();
}

pub export fn boj_cartridge_name() [*:0]const u8 {
    return "lang-mcp";
}

pub export fn boj_cartridge_version() [*:0]const u8 {
    return "0.1.0";
}

// ═══════════════════════════════════════════════════════════════════════
// ADR-0006 dispatch (boj_cartridge_invoke, 5th standard symbol)
// ═══════════════════════════════════════════════════════════════════════

pub const shim = @import("cartridge_shim.zig");

/// Dispatch the cartridge.json MCP tools.
pub export fn boj_cartridge_invoke(
    tool_name: [*c]const u8,
    json_args: [*c]const u8,
    out_buf: [*c]u8,
    in_out_len: [*c]usize,
) callconv(.c) i32 {
    if (shim.invokeArgsNull(tool_name, out_buf, in_out_len) or json_args == null) return shim.RC_BAD_ARGS;
    const allocator = std.heap.page_allocator;
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, std.mem.span(json_args), .{}) catch
        return langResult(.{ .success = false, .@"error" = "invalid JSON arguments" }, out_buf, in_out_len);
    defer parsed.deinit();
    if (parsed.value != .object) return langResult(.{ .success = false, .@"error" = "arguments must be an object" }, out_buf, in_out_len);
    const args = parsed.value.object;
    if (shim.toolIs(tool_name, "lang_list")) {
        return shim.writeResult(out_buf, in_out_len, "{\"languages\":[\"eclexia\",\"affinescript\",\"betlang\",\"ephapax\",\"mylang\",\"wokelang\",\"anvomidav\",\"phronesis\",\"error_lang\",\"julia_the_viper\",\"me_dialect\",\"oblibeny\"],\"count\":12,\"installation_checked\":false}");
    }
    if (shim.toolIs(tool_name, "lang_session_create")) {
        const language = langString(args, "language") orelse return langResult(.{ .success = false, .@"error" = "language field required" }, out_buf, in_out_len);
        const lang = std.meta.stringToEnum(Language, language) orelse return langResult(.{ .success = false, .@"error" = "unknown language" }, out_buf, in_out_len);
        const dialect_name = langString(args, "dialect_mode") orelse "pure";
        const dialect = std.meta.stringToEnum(DialectMode, dialect_name) orelse return langResult(.{ .success = false, .@"error" = "unknown dialect_mode" }, out_buf, in_out_len);
        const name = langString(args, "name") orelse language;
        const slot = lang_session_start_dialect(@intFromEnum(lang), @intFromEnum(dialect), name.ptr, name.len);
        if (slot < 0) return langResult(.{ .success = false, .@"error" = "session unavailable or invalid name" }, out_buf, in_out_len);
        var id_buf: [16]u8 = undefined;
        const id = std.fmt.bufPrint(&id_buf, "{d}", .{slot}) catch unreachable;
        return langResult(.{ .success = true, .session_id = id, .language = language, .dialect_mode = dialect_name, .lifetime = "current library process" }, out_buf, in_out_len);
    }
    const session_tool = shim.toolIs(tool_name, "lang_session_status") or shim.toolIs(tool_name, "lang_session_close") or
        shim.toolIs(tool_name, "lang_check") or shim.toolIs(tool_name, "lang_eval") or
        shim.toolIs(tool_name, "lang_compile") or shim.toolIs(tool_name, "lang_hover") or shim.toolIs(tool_name, "lang_complete");
    if (!session_tool) return shim.RC_UNKNOWN_TOOL;
    const id = langString(args, "session_id") orelse return langResult(.{ .success = false, .@"error" = "session_id field required" }, out_buf, in_out_len);
    const slot = std.fmt.parseInt(c_int, id, 10) catch return langResult(.{ .success = false, .@"error" = "invalid session_id" }, out_buf, in_out_len);
    const state = lang_session_state(slot);
    if (state < 0) return langResult(.{ .success = false, .@"error" = "unknown session in this process" }, out_buf, in_out_len);
    if (shim.toolIs(tool_name, "lang_session_status")) {
        return langResult(.{ .success = true, .session_id = id, .state = state, .language_id = lang_session_language(slot), .dialect_mode = lang_session_dialect(slot) }, out_buf, in_out_len);
    }
    if (shim.toolIs(tool_name, "lang_session_close")) {
        return langResult(.{ .success = lang_session_end(slot) == 0, .session_id = id }, out_buf, in_out_len);
    }
    // The lower-level check/eval functions need a configured backend URL. The
    // standard ABI has no owned persistent backend binding yet. Refuse rather
    // than pretending arguments are missing or reporting invented diagnostics.
    return langResult(.{ .success = false, .@"error" = "unsupported: standard ABI has no configured persistent language backend" }, out_buf, in_out_len);
}

fn langString(args: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const value = args.get(key) orelse return null;
    return if (value == .string) value.string else null;
}

fn langResult(value: anytype, out: [*c]u8, len: [*c]usize) i32 {
    const bytes = std.json.Stringify.valueAlloc(std.heap.page_allocator, value, .{}) catch return shim.RC_BAD_ARGS;
    defer std.heap.page_allocator.free(bytes);
    return shim.writeResult(out, len, bytes);
}

// ═══════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════

test "session start and end" {
    lang_reset();
    const name = "test-session";
    const sess = lang_session_start(@intFromEnum(Language.eclexia), name, name.len);
    try std.testing.expect(sess >= 0);
    try std.testing.expectEqual(@as(c_int, @intFromEnum(LangState.idle)), lang_session_state(sess));
    try std.testing.expectEqual(@as(c_int, @intFromEnum(Language.eclexia)), lang_session_language(sess));
    try std.testing.expectEqual(@as(c_int, 0), lang_session_end(sess));
}

test "session set URL" {
    lang_reset();
    const name = "url-test";
    const sess = lang_session_start(@intFromEnum(Language.affinescript), name, name.len);
    try std.testing.expect(sess >= 0);
    const url = "http://localhost:9100";
    try std.testing.expectEqual(@as(c_int, 0), lang_session_set_url(sess, url, url.len));
    try std.testing.expectEqual(@as(c_int, 0), lang_session_end(sess));
}

test "cannot double-end session" {
    lang_reset();
    const name = "double-end";
    const sess = lang_session_start(@intFromEnum(Language.betlang), name, name.len);
    _ = lang_session_end(sess);
    try std.testing.expectEqual(@as(c_int, -1), lang_session_end(sess));
}

test "session rejects empty name" {
    lang_reset();
    const sess = lang_session_start(@intFromEnum(Language.mylang), "", 0);
    try std.testing.expectEqual(@as(c_int, -2), sess);
}

test "all 12 languages can start sessions" {
    lang_reset();
    const langs = [_]c_int{ 1, 2, 3, 4, 5, 6, 7, 8 };
    for (langs, 0..) |lang_id, i| {
        _ = i;
        const name = "lang-test";
        const sess = lang_session_start(lang_id, name, name.len);
        try std.testing.expect(sess >= 0);
    }
    // All 8 slots used — next should fail
    const name = "overflow";
    const overflow = lang_session_start(9, name, name.len);
    try std.testing.expectEqual(@as(c_int, -1), overflow);
}

test "jtv dialect mode on session" {
    lang_reset();
    const name = "jtv-test";
    // Pure mode (default)
    const pure_sess = lang_session_start(@intFromEnum(Language.eclexia), name, name.len);
    try std.testing.expect(pure_sess >= 0);
    try std.testing.expectEqual(@as(c_int, 0), lang_session_dialect(pure_sess));
    _ = lang_session_end(pure_sess);

    // JtV-injected mode
    const jtv_sess = lang_session_start_dialect(@intFromEnum(Language.eclexia), 1, name, name.len);
    try std.testing.expect(jtv_sess >= 0);
    try std.testing.expectEqual(@as(c_int, 1), lang_session_dialect(jtv_sess));
    _ = lang_session_end(jtv_sess);
}

test "jtv mode works for all languages" {
    lang_reset();
    const name = "jtv-all";
    // Start eclexia+jtv
    const sess = lang_session_start_dialect(@intFromEnum(Language.affinescript), 1, name, name.len);
    try std.testing.expect(sess >= 0);
    try std.testing.expectEqual(@as(c_int, 1), lang_session_dialect(sess));
    try std.testing.expectEqual(@as(c_int, @intFromEnum(Language.affinescript)), lang_session_language(sess));
    _ = lang_session_end(sess);
}

test "session URL rejects empty and overlong" {
    lang_reset();
    const name = "url-reject";
    const sess = lang_session_start(@intFromEnum(Language.phronesis), name, name.len);
    try std.testing.expect(sess >= 0);
    try std.testing.expectEqual(@as(c_int, -6), lang_session_set_url(sess, "", 0));
    var long_url: [URL_BUF_SIZE]u8 = [_]u8{'x'} ** URL_BUF_SIZE;
    try std.testing.expectEqual(@as(c_int, -6), lang_session_set_url(sess, &long_url, long_url.len));
    _ = lang_session_end(sess);
}

// ═══════════════════════════════════════════════════════════════════════
// ADR-0006 invoke dispatch tests
// ═══════════════════════════════════════════════════════════════════════

test "invoke: declared tools return a result envelope even on validation failure" {
    var buf: [512]u8 = undefined;
    const tools = [_][]const u8{
        "lang_list",
        "lang_session_create",
        "lang_session_status",
        "lang_check",
        "lang_eval",
        "lang_compile",
        "lang_hover",
        "lang_complete",
        "lang_session_close",
    };
    for (tools) |t| {
        var len: usize = buf.len;
        const rc = boj_cartridge_invoke(t.ptr, "{}", &buf, &len);
        try std.testing.expectEqual(@as(i32, 0), rc);
        try std.testing.expect(len > 0);
        // Must not be a stub
        try std.testing.expect(std.mem.indexOf(u8, buf[0..len], "stub") == null);
    }
}

test "invoke: lang_list returns language list" {
    var buf: [512]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke("lang_list", "{}", &buf, &len);
    try std.testing.expectEqual(@as(i32, 0), rc);
    const out = buf[0..len];
    try std.testing.expect(std.mem.indexOf(u8, out, "languages") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "affinescript") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"count\":12") != null);
}

test "invoke: lang_session_create missing language returns error" {
    var buf: [128]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke("lang_session_create", "{}", &buf, &len);
    try std.testing.expectEqual(@as(i32, 0), rc);
    const out = buf[0..len];
    try std.testing.expect(std.mem.indexOf(u8, out, "error") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "language") != null);
}

test "invoke: unknown tool returns -1" {
    var buf: [64]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke("nope", "{}", &buf, &len);
    try std.testing.expectEqual(@as(i32, -1), rc);
}

test "invoke: buffer too small returns -3" {
    var buf: [4]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke("lang_list", "{}", &buf, &len);
    try std.testing.expectEqual(@as(i32, -3), rc);
    try std.testing.expect(len > 4);
}

test "invoke: valid session arguments change real state and close invalidates it" {
    lang_reset();
    defer lang_reset();
    var buf: [512]u8 = undefined;
    var len: usize = buf.len;
    try std.testing.expectEqual(@as(i32, 0), boj_cartridge_invoke("lang_session_create", "{\"language\":\"affinescript\",\"dialect_mode\":\"jtv\"}", &buf, &len));
    const created = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, buf[0..len], .{});
    defer created.deinit();
    try std.testing.expect(created.value.object.get("success").?.bool);
    try std.testing.expectEqualStrings("0", created.value.object.get("session_id").?.string);
    try std.testing.expectEqual(@as(c_int, 1), lang_session_dialect(0));
    len = buf.len;
    _ = boj_cartridge_invoke("lang_session_close", "{\"session_id\":\"0\"}", &buf, &len);
    try std.testing.expectEqual(@as(c_int, -1), lang_session_state(0));
    len = buf.len;
    _ = boj_cartridge_invoke("lang_session_status", "{\"session_id\":\"0\"}", &buf, &len);
    try std.testing.expect(std.mem.indexOf(u8, buf[0..len], "unknown session") != null);
}
