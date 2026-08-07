// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Lang-MCP Cartridge — adapter build configuration (Zig 0.14+).

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ffi_mod = b.createModule(.{
        .root_source_file = b.path("../ffi/lang_ffi.zig"),
        .target = target,
        .optimize = optimize,
    });

    const adapter_mod = b.createModule(.{
        .root_source_file = b.path("lang_adapter.zig"),
        .target = target,
        .optimize = optimize,
    });
    adapter_mod.addImport("lang_ffi", ffi_mod);

    const adapter = b.addExecutable(.{
        .name = "lang-adapter",
        .root_module = adapter_mod,
    });
    b.installArtifact(adapter);

    const run_step = b.step("run", "Run the lang-mcp adapter");
    run_step.dependOn(&b.addRunArtifact(adapter).step);

    const adapter_tests = b.addTest(.{ .root_module = adapter_mod });
    const run_tests = b.addRunArtifact(adapter_tests);
    const test_step = b.step("test", "Run lang-mcp adapter tests");
    test_step.dependOn(&run_tests.step);
}
