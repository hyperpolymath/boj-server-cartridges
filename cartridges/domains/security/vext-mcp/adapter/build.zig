// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// vext-mcp/adapter/build.zig

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ffi_mod = b.createModule(.{
        .root_source_file = b.path("../ffi/vext_ffi.zig"),
        .target = target,
        .optimize = optimize,
    });
    // The sibling FFI library links libc (see ../ffi/build.zig); the
    // adapter embeds the same source, so it must link it too.
    ffi_mod.link_libc = true;

    const adapter_mod = b.createModule(.{
        .root_source_file = b.path("vext_adapter.zig"),
        .target = target,
        .optimize = optimize,
    });
    adapter_mod.addImport("vext_ffi", ffi_mod);

    const adapter = b.addExecutable(.{
        .name = "vext_adapter",
        .root_module = adapter_mod,
    });
    b.installArtifact(adapter);

    const run_step = b.step("run", "Run the vext-mcp adapter");
    run_step.dependOn(&b.addRunArtifact(adapter).step);

    const adapter_tests = b.addTest(.{ .root_module = adapter_mod });
    const run_tests = b.addRunArtifact(adapter_tests);
    const test_step = b.step("test", "Run vext-mcp adapter tests");
    test_step.dependOn(&run_tests.step);
}
