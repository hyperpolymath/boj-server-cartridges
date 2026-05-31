// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Cartridge ABI module (ADR-0006 five-symbol surface). Its root imports the
    // Zig perception core under src/ and the shared cartridge shim.
    const ffi_mod = b.createModule(.{
        .root_source_file = b.path("npc_mcp_ffi.zig"),
        .target = target,
        .optimize = optimize,
    });

    // The shared library the host loads: ffi/zig-out/lib/libnpc_mcp.so.
    const lib = b.addLibrary(.{
        .name = "npc_mcp",
        .linkage = .dynamic,
        .root_module = ffi_mod,
    });
    lib.linkLibC();
    b.installArtifact(lib);

    // Unit tests: the cartridge ABI plus the perception core it imports
    // (npcmcp.zig pulls every perception/command module via refAllDeclsRecursive).
    const tests = b.addTest(.{ .root_module = ffi_mod });
    tests.linkLibC();
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run FFI and core unit tests");
    test_step.dependOn(&run_tests.step);

    // Integration tests: a synthetic JSONL event stream through the core.
    const core_mod = b.createModule(.{
        .root_source_file = b.path("src/npcmcp.zig"),
        .target = target,
        .optimize = optimize,
    });
    const integration_mod = b.createModule(.{
        .root_source_file = b.path("../tests/integration/synthetic_stream.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "npcmcp", .module = core_mod }},
    });
    const integration = b.addTest(.{ .root_module = integration_mod });
    const run_integration = b.addRunArtifact(integration);
    const integration_step = b.step("integration", "Run integration tests");
    integration_step.dependOn(&run_integration.step);
}
