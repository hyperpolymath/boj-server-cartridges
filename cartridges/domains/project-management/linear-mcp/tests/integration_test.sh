#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Integration tests for the linear-mcp cartridge.
#
# Categories exercised (proven-tests-and-benches Taxonomy.idr):
#   BuildTest       — the FFI compiles
#   UnitTest        — Zig unit tests + mod.js unit tests
#   PropertyTest    — priority range, page-size clamping
#   RegressionTest  — raw-vs-Bearer key; RATELIMITED as HTTP 400
#   ContractTest    — parity_test.sh
#   ProofRegression — Idris2 ABI typechecks
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CART_DIR="$(dirname "$SCRIPT_DIR")"
FFI_DIR="$CART_DIR/ffi"

echo "=== linear-mcp integration tests ==="

# The repo pins zig 0.15.1 in .tool-versions. Zig 0.16 removed
# std.meta.intToEnum and Compile.linkLibC, which this FFI and its build.zig
# still use, so 0.16 fails to build for reasons unrelated to the cartridge.
if command -v zig >/dev/null 2>&1; then
    ZIG_V="$(zig version)"
    case "$ZIG_V" in
        0.15.*) ;;
        *) echo "  WARN: zig $ZIG_V — repo pins 0.15.1; build may fail on removed APIs" ;;
    esac

    echo "[1/5] Building FFI..."
    (cd "$FFI_DIR" && zig build)

    echo "[2/5] Zig unit tests..."
    (cd "$FFI_DIR" && zig build test)
else
    echo "[1-2/5] SKIPPED (zig not in PATH)"
fi

echo "[3/5] Contract parity (cartridge.json <-> mod.js <-> FFI)..."
bash "$SCRIPT_DIR/parity_test.sh"

echo "[4/5] mod.js unit / property / regression tests..."
if command -v deno >/dev/null 2>&1; then
    (cd "$CART_DIR" && deno test --allow-env --quiet tests/unit_test.js)
else
    echo "  SKIPPED (deno not in PATH)"
fi

echo "[5/5] Idris2 ABI..."
if command -v idris2 >/dev/null 2>&1; then
    (cd "$CART_DIR/abi" && idris2 --check linear_mcp.ipkg)
    echo "  ABI: OK"
else
    echo "  ABI: SKIPPED (idris2 not in PATH)"
fi

echo ""
echo "All tests passed for linear-mcp!"
