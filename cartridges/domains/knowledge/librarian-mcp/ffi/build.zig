// SPDX-License-Identifier: MPL-2.0
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Shared module for the library and its tests.
    const root_module = b.createModule(.{
        .root_source_file = b.path("src/librarian.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Static library with C ABI exports, for standalone linkage.
    const static_lib = b.addLibrary(.{
        .name = "librarian_ffi",
        .linkage = .static,
        .root_module = root_module,
    });
    b.installArtifact(static_lib);

    // Shared library with the cartridge-standard name; boj-server looks for
    // cartridges/<name>-mcp/ffi/zig-out/lib/lib<name>_mcp.so when linking the
    // V-lang adapter. Mirrors the convention used by the stock cartridges.
    const shared_lib = b.addLibrary(.{
        .name = "librarian_mcp",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/librarian.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(shared_lib);

    // Unit tests; aggregated via root librarian.zig which uses
    // std.testing.refAllDeclsRecursive to pull in every module.
    const tests = b.addTest(.{
        .root_module = root_module,
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run all FFI tests");
    test_step.dependOn(&run_tests.step);

    // Integration tests; top-level synthetic corpus build-then-query scenarios.
    const integration_module = b.createModule(.{
        .root_source_file = b.path("../tests/integration/synthetic_corpus.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "librarian", .module = root_module },
        },
    });
    const integration = b.addTest(.{
        .root_module = integration_module,
    });
    const run_integration = b.addRunArtifact(integration);
    const integration_step = b.step("integration", "Run integration tests");
    integration_step.dependOn(&run_integration.step);
}
