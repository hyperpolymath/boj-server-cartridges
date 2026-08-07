// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// opsm-mcp/adapter/build.zig — build configuration for the unified adapter.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ffi_mod = b.createModule(.{
        .root_source_file = b.path("../ffi/opsm_ffi.zig"),
        .target = target,
        .optimize = optimize,
    });

    const adapter_mod = b.createModule(.{
        .root_source_file = b.path("opsm_adapter.zig"),
        .target = target,
        .optimize = optimize,
    });
    adapter_mod.addImport("opsm_ffi", ffi_mod);

    const adapter = b.addExecutable(.{
        .name = "opsm_adapter",
        .root_module = adapter_mod,
    });
    b.installArtifact(adapter);

    const run_step = b.step("run", "Run the opsm-mcp adapter");
    run_step.dependOn(&b.addRunArtifact(adapter).step);

    const adapter_tests = b.addTest(.{ .root_module = adapter_mod });
    const run_tests = b.addRunArtifact(adapter_tests);
    const test_step = b.step("test", "Run opsm-mcp adapter tests");
    test_step.dependOn(&run_tests.step);
}
