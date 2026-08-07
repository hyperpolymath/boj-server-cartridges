// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// LSP-MCP Cartridge — adapter build configuration (Zig 0.14+).
//
// Builds the `lsp-adapter` binary: the unified REST/gRPC-compat/GraphQL server
// that wraps the lsp_ffi.zig session state machine.
//
// Usage:
//   zig build         -- build lsp-adapter binary
//   zig build run     -- build and run (REST :9016, gRPC-compat :9017, GraphQL :9018)
//   zig build test    -- run unit tests

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ffi_mod = b.createModule(.{
        .root_source_file = b.path("../ffi/lsp_ffi.zig"),
        .target = target,
        .optimize = optimize,
    });

    const adapter_mod = b.createModule(.{
        .root_source_file = b.path("lsp_adapter.zig"),
        .target = target,
        .optimize = optimize,
    });
    adapter_mod.addImport("lsp_ffi", ffi_mod);

    const adapter = b.addExecutable(.{
        .name = "lsp-adapter",
        .root_module = adapter_mod,
    });
    b.installArtifact(adapter);

    const run_step = b.step("run", "Run the lsp-mcp adapter");
    run_step.dependOn(&b.addRunArtifact(adapter).step);

    const adapter_tests = b.addTest(.{ .root_module = adapter_mod });
    const run_tests = b.addRunArtifact(adapter_tests);
    const test_step = b.step("test", "Run lsp-mcp adapter tests");
    test_step.dependOn(&run_tests.step);
}
