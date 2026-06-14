// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Model Router FFI — LLM tier routing for BoJ MCP cartridge.
//
// Implements ADR-0006 five-symbol ABI. All classification logic is a
// pure keyword-based port of mod.js — no regex, no heap, no network.

const std = @import("std");
const shim = @import("cartridge_shim.zig");

pub const ModelTier = enum(i32) {
    haiku = 0,
    sonnet = 1,
    opus = 2,
};

/// Select model based on cost preference (0=cheapest, 100=best quality).
pub export fn router_select(cost_pref: i32) i32 {
    if (cost_pref < 30) return 0; // Haiku
    if (cost_pref < 70) return 1; // Sonnet
    return 2; // Opus
}

/// Fallback: Opus→Sonnet, Sonnet→Haiku, Haiku→-1 (no fallback).
pub export fn router_fallback(tier: i32) i32 {
    return switch (@as(ModelTier, @enumFromInt(tier))) {
        .opus => 1,
        .sonnet => 0,
        .haiku => -1,
    };
}

// ═══════════════════════════════════════════════════════════════════════
// Standard ABI (ADR-0005 four symbols + ADR-0006 invoke)
// ═══════════════════════════════════════════════════════════════════════

const CARTRIDGE_NAME_PTR: [*:0]const u8 = "model-router-mcp";
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

// ─── helpers ────────────────────────────────────────────────────────────

/// Case-insensitive substring search. Returns true if `haystack` contains
/// `needle` after lowercasing both.  Uses the arena allocator for scratch.
fn containsCI(allocator: std.mem.Allocator, haystack: []const u8, needle: []const u8) bool {
    const hay_lower = allocator.alloc(u8, haystack.len) catch return false;
    defer allocator.free(hay_lower);
    for (haystack, 0..) |c, i| hay_lower[i] = std.ascii.toLower(c);
    return std.mem.indexOf(u8, hay_lower, needle) != null;
}

/// Escape a string for JSON: replace \ → \\ and " → \" and control chars.
/// Writes into `out_buf` and returns the slice written.  Truncates at
/// `max_len` bytes (adds "…" suffix) to keep output bounded.
fn jsonEscape(
    out_buf: []u8,
    src: []const u8,
    max_len: usize,
) []const u8 {
    const src_used = @min(src.len, max_len);
    var wi: usize = 0;
    for (src[0..src_used]) |c| {
        if (wi + 6 > out_buf.len) break; // leave room for any two-char escape
        switch (c) {
            '\\' => {
                out_buf[wi] = '\\';
                out_buf[wi + 1] = '\\';
                wi += 2;
            },
            '"' => {
                out_buf[wi] = '\\';
                out_buf[wi + 1] = '"';
                wi += 2;
            },
            '\n' => {
                out_buf[wi] = '\\';
                out_buf[wi + 1] = 'n';
                wi += 2;
            },
            '\r' => {
                out_buf[wi] = '\\';
                out_buf[wi + 1] = 'r';
                wi += 2;
            },
            '\t' => {
                out_buf[wi] = '\\';
                out_buf[wi + 1] = 't';
                wi += 2;
            },
            else => {
                out_buf[wi] = c;
                wi += 1;
            },
        }
    }
    return out_buf[0..wi];
}

// ─── classify_task ──────────────────────────────────────────────────────

const Complexity = enum { expert, complex, trivial, simple, moderate };

const Classification = struct {
    complexity: Complexity,
    model: []const u8,
    confidence_x100: u32, // e.g. 90 means 0.90
    reason: []const u8,
    can_delegate: bool,
};

/// Pure keyword-based port of mod.js classifyTask.
/// `task` is a UTF-8 string (may be empty).
fn classifyTask(allocator: std.mem.Allocator, task: []const u8) Classification {
    // Expert patterns — all lowercased needles
    const expert_needles = [_][]const u8{
        "formal verif", "formalverif",
        "dependent type", "dependenttype",
        "idris",
        "prove", "proof", "theorem",
        "architecture", "redesign", "refactor across",
        "security audit", "vulnerability",
        "design system", "system design",
        "migrate codebase",
        "cross-repo", "across repos",
        "critical decision",
        "believe_me", "assert_total", "sorry", "admitted",
    };
    for (expert_needles) |needle| {
        if (containsCI(allocator, task, needle)) {
            return .{ .complexity = .expert, .model = "opus", .confidence_x100 = 90, .reason = "Expert signal detected", .can_delegate = false };
        }
    }

    // Complex patterns
    const complex_needles = [_][]const u8{
        "implement", "feature",
        "build system",
        "create module",
        "debug", "investigate",
        "review code", "audit code",
        "multiple files", "several files",
        "wire together", "integrate",
        "protocol", "specification",
    };
    for (complex_needles) |needle| {
        if (containsCI(allocator, task, needle)) {
            return .{ .complexity = .complex, .model = "opus", .confidence_x100 = 75, .reason = "Complex signal detected", .can_delegate = true };
        }
    }

    // Trivial patterns — check task start for common read-only verbs
    const trivial_start_needles = [_][]const u8{
        "list ", "show ", "what is", "check ", "status ", "count ", "find ", "search ", "grep ", "glob ",
        "read ", "cat ", "head ", "tail ", "ls ",
    };
    for (trivial_start_needles) |needle| {
        // match at start (case-insensitive) OR anywhere for git status etc.
        const hay_lower = allocator.alloc(u8, task.len) catch continue;
        defer allocator.free(hay_lower);
        for (task, 0..) |c, i| hay_lower[i] = std.ascii.toLower(c);
        if (std.mem.startsWith(u8, hay_lower, needle)) {
            return .{ .complexity = .trivial, .model = "haiku", .confidence_x100 = 85, .reason = "Trivial read-only command", .can_delegate = false };
        }
    }
    // git shorthand (anywhere in string)
    const trivial_anywhere = [_][]const u8{ "git status", "git log", "git branch", "how many", "what files" };
    for (trivial_anywhere) |needle| {
        if (containsCI(allocator, task, needle)) {
            return .{ .complexity = .trivial, .model = "haiku", .confidence_x100 = 85, .reason = "Trivial read-only command", .can_delegate = false };
        }
    }

    // Simple patterns
    const simple_needles = [_][]const u8{
        "rename", "replace",
        "fix typo", "update version",
        "add header", "add spdx", "add license",
        "delete file", "remove file", "clean up",
        "format", "lint", "prettier",
        "commit", "push", "pull",
    };
    for (simple_needles) |needle| {
        if (containsCI(allocator, task, needle)) {
            return .{ .complexity = .simple, .model = "haiku", .confidence_x100 = 70, .reason = "Simple mechanical task", .can_delegate = false };
        }
    }

    // Word-count heuristics
    var word_count: u32 = 0;
    var in_word = false;
    for (task) |c| {
        const is_space = c == ' ' or c == '\t' or c == '\n' or c == '\r';
        if (!is_space and !in_word) {
            word_count += 1;
            in_word = true;
        } else if (is_space) {
            in_word = false;
        }
    }

    if (word_count < 10) {
        return .{ .complexity = .simple, .model = "sonnet", .confidence_x100 = 50, .reason = "Short prompt", .can_delegate = false };
    }
    if (word_count > 100) {
        return .{ .complexity = .complex, .model = "opus", .confidence_x100 = 60, .reason = "Long detailed prompt", .can_delegate = true };
    }

    return .{ .complexity = .moderate, .model = "sonnet", .confidence_x100 = 50, .reason = "No strong signals, defaulting to Sonnet", .can_delegate = true };
}

fn complexityName(c: Complexity) []const u8 {
    return switch (c) {
        .expert => "expert",
        .complex => "complex",
        .trivial => "trivial",
        .simple => "simple",
        .moderate => "moderate",
    };
}

fn handleClassifyTask(
    json_args: [*c]const u8,
    out_buf: [*c]u8,
    in_out_len: [*c]usize,
) i32 {
    var arena_mem: [256 * 1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&arena_mem);
    const allocator = fba.allocator();

    const args_str: []const u8 = if (json_args != null)
        std.mem.span(@as([*:0]const u8, @ptrCast(json_args)))
    else
        "{}";

    // Extract "task" field via JSON parse; fall back to empty string.
    var task: []const u8 = "";
    if (std.json.parseFromSlice(std.json.Value, allocator, args_str, .{})) |parsed| {
        defer parsed.deinit();
        if (parsed.value == .object) {
            if (parsed.value.object.get("task")) |val| {
                if (val == .string) {
                    task = val.string;
                }
            }
        }
    } else |_| {}

    // Empty / missing task → default moderate result (probe-friendly).
    if (task.len == 0) {
        const body =
            \\{"complexity":"moderate","model":"sonnet","confidence":0.5,"reason":"No task specified","canDelegate":false}
        ;
        return shim.writeResult(out_buf, in_out_len, body);
    }

    const cl = classifyTask(allocator, task);

    // Confidence as decimal string (two sig figs).
    const conf_int = cl.confidence_x100 / 100;
    const conf_frac = cl.confidence_x100 % 100;

    // Escape the reason (safe ASCII, but guard anyway).
    var reason_esc_buf: [256]u8 = undefined;
    const reason_esc = jsonEscape(&reason_esc_buf, cl.reason, 200);

    var result_buf: [1024]u8 = undefined;
    const result = std.fmt.bufPrint(
        &result_buf,
        "{{\"complexity\":\"{s}\",\"model\":\"{s}\",\"confidence\":{d}.{d:0>2},\"reason\":\"{s}\",\"canDelegate\":{s}}}",
        .{
            complexityName(cl.complexity),
            cl.model,
            conf_int,
            conf_frac,
            reason_esc,
            if (cl.can_delegate) "true" else "false",
        },
    ) catch return shim.RC_RUNTIME_ERROR;

    return shim.writeResult(out_buf, in_out_len, result);
}

// ─── plan_delegation ────────────────────────────────────────────────────

fn handlePlanDelegation(
    json_args: [*c]const u8,
    out_buf: [*c]u8,
    in_out_len: [*c]usize,
) i32 {
    var arena_mem: [256 * 1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&arena_mem);
    const allocator = fba.allocator();

    const args_str: []const u8 = if (json_args != null)
        std.mem.span(@as([*:0]const u8, @ptrCast(json_args)))
    else
        "{}";

    var task: []const u8 = "";
    var target_model: []const u8 = "";

    if (std.json.parseFromSlice(std.json.Value, allocator, args_str, .{})) |parsed| {
        defer parsed.deinit();
        if (parsed.value == .object) {
            if (parsed.value.object.get("task")) |val| {
                if (val == .string) task = val.string;
            }
            if (parsed.value.object.get("target_model")) |val| {
                if (val == .string) target_model = val.string;
            }
        }
    } else |_| {}

    if (task.len == 0 or target_model.len == 0) {
        const body =
            \\{"plan":"Provide task and target_model fields to generate a delegation plan","target_model":null}
        ;
        return shim.writeResult(out_buf, in_out_len, body);
    }

    // Escape user-supplied fields.
    var task_esc_buf: [512]u8 = undefined;
    const task_esc = jsonEscape(&task_esc_buf, task, 400);

    var model_esc_buf: [64]u8 = undefined;
    const model_esc = jsonEscape(&model_esc_buf, target_model, 60);

    // Build the delegation plan (mirrors mod.js generateDelegationPlan).
    var plan_buf: [2048]u8 = undefined;
    const plan = std.fmt.bufPrint(
        &plan_buf,
        "You are executing a pre-planned task. Follow these instructions EXACTLY.\\n" ++
            "Do not deviate, improvise, or add anything not specified.\\n" ++
            "If you encounter something unexpected, STOP and report it.\\n\\n" ++
            "MODEL: {s}\\n" ++
            "ORIGINAL TASK: {s}\\n\\n" ++
            "CHECKPOINTS:\\n" ++
            "- After each file edit, verify it compiles/builds\\n" ++
            "- After completing all steps, run tests if available\\n" ++
            "- Report: what was done, what succeeded, what failed\\n\\n" ++
            "ESCALATION: If any step fails, output ESCALATE: <reason> and stop.",
        .{ model_esc, task_esc },
    ) catch return shim.RC_RUNTIME_ERROR;

    var result_buf: [4096]u8 = undefined;
    const result = std.fmt.bufPrint(
        &result_buf,
        "{{\"plan\":\"{s}\",\"target_model\":\"{s}\"}}",
        .{ plan, model_esc },
    ) catch return shim.RC_RUNTIME_ERROR;

    return shim.writeResult(out_buf, in_out_len, result);
}

// ─── review_output ──────────────────────────────────────────────────────

fn handleReviewOutput(
    json_args: [*c]const u8,
    out_buf: [*c]u8,
    in_out_len: [*c]usize,
) i32 {
    var arena_mem: [256 * 1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&arena_mem);
    const allocator = fba.allocator();

    const args_str: []const u8 = if (json_args != null)
        std.mem.span(@as([*:0]const u8, @ptrCast(json_args)))
    else
        "{}";

    var original_task: []const u8 = "";
    var executor_output: []const u8 = "";

    if (std.json.parseFromSlice(std.json.Value, allocator, args_str, .{})) |parsed| {
        defer parsed.deinit();
        if (parsed.value == .object) {
            if (parsed.value.object.get("original_task")) |val| {
                if (val == .string) original_task = val.string;
            }
            if (parsed.value.object.get("executor_output")) |val| {
                if (val == .string) executor_output = val.string;
            }
        }
    } else |_| {}

    if (original_task.len == 0 or executor_output.len == 0) {
        const body =
            \\{"verdict":"MISSING_INPUT","notes":"original_task and executor_output required","review_prompt":null}
        ;
        return shim.writeResult(out_buf, in_out_len, body);
    }

    var task_esc_buf: [512]u8 = undefined;
    const task_esc = jsonEscape(&task_esc_buf, original_task, 400);

    var output_esc_buf: [1024]u8 = undefined;
    const output_esc = jsonEscape(&output_esc_buf, executor_output, 800);

    var review_buf: [4096]u8 = undefined;
    const review = std.fmt.bufPrint(
        &review_buf,
        "Review the following work done by a delegated model.\\n\\n" ++
            "ORIGINAL TASK: {s}\\n\\n" ++
            "EXECUTOR OUTPUT:\\n{s}\\n\\n" ++
            "CHECK:\\n" ++
            "1. Was the task completed correctly?\\n" ++
            "2. Were there any errors, omissions, or quality issues?\\n" ++
            "3. Does the output match the intent of the original task?\\n" ++
            "4. Are there any security concerns?\\n\\n" ++
            "VERDICT: [APPROVED / NEEDS_REVISION / FAILED]\\n" ++
            "NOTES: [Specific feedback if not approved]",
        .{ task_esc, output_esc },
    ) catch return shim.RC_RUNTIME_ERROR;

    var result_buf: [8192]u8 = undefined;
    const result = std.fmt.bufPrint(
        &result_buf,
        "{{\"verdict\":\"PENDING\",\"review_prompt\":\"{s}\"}}",
        .{review},
    ) catch return shim.RC_RUNTIME_ERROR;

    return shim.writeResult(out_buf, in_out_len, result);
}

// ─── estimate_cost ──────────────────────────────────────────────────────

fn handleEstimateCost(
    json_args: [*c]const u8,
    out_buf: [*c]u8,
    in_out_len: [*c]usize,
) i32 {
    var arena_mem: [64 * 1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&arena_mem);
    const allocator = fba.allocator();

    const args_str: []const u8 = if (json_args != null)
        std.mem.span(@as([*:0]const u8, @ptrCast(json_args)))
    else
        "{}";

    // Extract estimated_tokens (integer or float in JSON).
    var estimated_tokens: i64 = 0;
    var has_tokens = false;

    if (std.json.parseFromSlice(std.json.Value, allocator, args_str, .{})) |parsed| {
        defer parsed.deinit();
        if (parsed.value == .object) {
            if (parsed.value.object.get("estimated_tokens")) |val| {
                switch (val) {
                    .integer => |n| {
                        estimated_tokens = n;
                        has_tokens = true;
                    },
                    .float => |f| {
                        estimated_tokens = @intFromFloat(f);
                        has_tokens = true;
                    },
                    else => {},
                }
            }
        }
    } else |_| {}

    if (!has_tokens) {
        // Return a default cost estimate for 0 tokens with an informational message.
        const body =
            \\{"opus":0,"sonnet":0,"haiku":0,"delegated":0,"savings":"80%","note":"Provide estimated_tokens to calculate real costs"}
        ;
        return shim.writeResult(out_buf, in_out_len, body);
    }

    // Port of mod.js estimateCost. Rates per token (scaled x1000 for integer math):
    //   opus = 1.0, sonnet = 0.2, haiku = 0.04
    //   delegated = tokens*0.1*opus + tokens*0.9*haiku + tokens*0.1*opus
    //             = tokens*(0.1 + 0.036 + 0.1) = tokens*0.236
    //
    // We keep the values as integer microcents (multiply by 1000) to avoid
    // floating-point formatting complexity, then present as integers matching
    // the JS Math.round() output.
    const t = estimated_tokens;
    const opus: i64 = t; // t * 1.0
    const sonnet: i64 = @divTrunc(t * 20, 100); // t * 0.20
    const haiku: i64 = @divTrunc(t * 4, 100); // t * 0.04
    // delegated = t*0.1 + t*0.9*0.04 + t*0.1 = t*(0.1+0.036+0.1) = t*0.236
    const delegated: i64 = @divTrunc(t * 236, 1000);

    // savings = round((1 - delegated/opus) * 100)%
    // guard against division by zero
    var savings: i64 = 80; // default ~80% when tokens=0
    if (opus != 0) {
        savings = @divTrunc((opus - delegated) * 100, opus);
    }

    var result_buf: [512]u8 = undefined;
    const result = std.fmt.bufPrint(
        &result_buf,
        "{{\"opus\":{d},\"sonnet\":{d},\"haiku\":{d},\"delegated\":{d},\"savings\":\"{d}%\"}}",
        .{ opus, sonnet, haiku, delegated, savings },
    ) catch return shim.RC_RUNTIME_ERROR;

    return shim.writeResult(out_buf, in_out_len, result);
}

// ═══════════════════════════════════════════════════════════════════════
// ADR-0006 dispatch
// ═══════════════════════════════════════════════════════════════════════

export fn boj_cartridge_invoke(
    tool_name: [*c]const u8,
    json_args: [*c]const u8,
    out_buf: [*c]u8,
    in_out_len: [*c]usize,
) callconv(.c) i32 {
    if (shim.invokeArgsNull(tool_name, out_buf, in_out_len)) return shim.RC_BAD_ARGS;

    if (shim.toolIs(tool_name, "classify_task"))
        return handleClassifyTask(json_args, out_buf, in_out_len);
    if (shim.toolIs(tool_name, "plan_delegation"))
        return handlePlanDelegation(json_args, out_buf, in_out_len);
    if (shim.toolIs(tool_name, "review_output"))
        return handleReviewOutput(json_args, out_buf, in_out_len);
    if (shim.toolIs(tool_name, "estimate_cost"))
        return handleEstimateCost(json_args, out_buf, in_out_len);

    return shim.RC_UNKNOWN_TOOL;
}

// ═══════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════

test "model selection" {
    try std.testing.expectEqual(@as(i32, 0), router_select(0));
    try std.testing.expectEqual(@as(i32, 1), router_select(50));
    try std.testing.expectEqual(@as(i32, 2), router_select(100));
}

test "fallback chain terminates" {
    try std.testing.expectEqual(@as(i32, 1), router_fallback(2));
    try std.testing.expectEqual(@as(i32, 0), router_fallback(1));
    try std.testing.expectEqual(@as(i32, -1), router_fallback(0));
}

test "boj_cartridge_name returns model-router-mcp" {
    const n = std.mem.span(boj_cartridge_name());
    try std.testing.expectEqualStrings("model-router-mcp", n);
}

test "boj_cartridge_init returns 0" {
    try std.testing.expectEqual(@as(c_int, 0), boj_cartridge_init());
}

test "invoke: classify_task empty args returns non-stub default" {
    var buf: [256]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke("classify_task", "{}", &buf, &len);
    try std.testing.expectEqual(@as(i32, 0), rc);
    const out = buf[0..len];
    try std.testing.expect(std.mem.indexOf(u8, out, "stub") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "moderate") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "sonnet") != null);
}

test "invoke: classify_task expert signal" {
    var buf: [512]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke("classify_task", "{\"task\":\"prove the theorem\"}", &buf, &len);
    try std.testing.expectEqual(@as(i32, 0), rc);
    const out = buf[0..len];
    try std.testing.expect(std.mem.indexOf(u8, out, "expert") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "opus") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "stub") == null);
}

test "invoke: classify_task trivial signal" {
    var buf: [512]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke("classify_task", "{\"task\":\"list all files\"}", &buf, &len);
    try std.testing.expectEqual(@as(i32, 0), rc);
    const out = buf[0..len];
    try std.testing.expect(std.mem.indexOf(u8, out, "trivial") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "haiku") != null);
}

test "invoke: each declared tool succeeds" {
    var buf: [512]u8 = undefined;
    const tools = [_][]const u8{
        "classify_task", "plan_delegation", "review_output", "estimate_cost",
    };
    for (tools) |t| {
        var len: usize = buf.len;
        const rc = boj_cartridge_invoke(t.ptr, "{}", &buf, &len);
        try std.testing.expectEqual(@as(i32, 0), rc);
        // None should contain "stub"
        try std.testing.expect(std.mem.indexOf(u8, buf[0..len], "stub") == null);
    }
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
    const rc = boj_cartridge_invoke("classify_task", "{}", &buf, &len);
    try std.testing.expectEqual(@as(i32, -3), rc);
    try std.testing.expect(len > 4);
}

test "invoke: estimate_cost with tokens" {
    var buf: [512]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke("estimate_cost", "{\"estimated_tokens\":1000}", &buf, &len);
    try std.testing.expectEqual(@as(i32, 0), rc);
    const out = buf[0..len];
    try std.testing.expect(std.mem.indexOf(u8, out, "opus") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "savings") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "stub") == null);
}

test "invoke: plan_delegation missing args returns guidance" {
    var buf: [512]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke("plan_delegation", "{}", &buf, &len);
    try std.testing.expectEqual(@as(i32, 0), rc);
    const out = buf[0..len];
    try std.testing.expect(std.mem.indexOf(u8, out, "plan") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "stub") == null);
}

test "invoke: review_output missing args returns guidance" {
    var buf: [512]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke("review_output", "{}", &buf, &len);
    try std.testing.expectEqual(@as(i32, 0), rc);
    const out = buf[0..len];
    try std.testing.expect(std.mem.indexOf(u8, out, "MISSING_INPUT") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "stub") == null);
}
