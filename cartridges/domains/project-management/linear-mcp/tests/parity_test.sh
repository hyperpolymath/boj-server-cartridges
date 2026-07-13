#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# ContractTest (proven-tests-and-benches Taxonomy.idr: ContractTest).
#
# The linear-mcp tool list is declared in three independent places:
#
#   1. cartridge.json          — what the cartridge advertises to the host
#   2. mod.js                  — what it actually implements (the live runtime)
#   3. ffi/linear_mcp_ffi.zig  — the ADR-0006 TOOLS table
#
# Nothing in the build forces those three to agree, so they drift. The
# pre-0.2.0 cartridge is the cautionary tale: minter.toml said "GraphQL",
# cartridge.json said "REST", and the ABI already modelled 16 actions while the
# manifest exposed 7. This test fails on any such divergence.
set -euo pipefail

CART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$CART_DIR"

echo "=== linear-mcp parity (cartridge.json <-> mod.js <-> FFI) ==="

python3 - <<'PY'
import json, re, sys

declared = [t["name"] for t in json.load(open("cartridge.json"))["tools"]]

impl = re.findall(r'case "(linear_[a-z_]+)"', open("mod.js").read())

zig = open("ffi/linear_mcp_ffi.zig").read()
table = re.search(r"pub const TOOLS = \[_\]\[\]const u8\{(.*?)\};", zig, re.S)
ffi = re.findall(r'"(linear_[a-z_]+)"', table.group(1)) if table else []

fail = 0

def cmp(a_name, a, b_name, b):
    global fail
    only_a, only_b = sorted(set(a) - set(b)), sorted(set(b) - set(a))
    if only_a:
        print(f"  FAIL in {a_name} but not {b_name}: {only_a}"); fail = 1
    if only_b:
        print(f"  FAIL in {b_name} but not {a_name}: {only_b}"); fail = 1

cmp("cartridge.json", declared, "mod.js", impl)
cmp("cartridge.json", declared, "ffi TOOLS", ffi)

for name, xs in (("cartridge.json", declared), ("mod.js", impl), ("ffi TOOLS", ffi)):
    dupes = sorted({x for x in xs if xs.count(x) > 1})
    if dupes:
        print(f"  FAIL duplicate tool names in {name}: {dupes}"); fail = 1

# metadata.toolCount must not lie about the size of the surface.
m = re.search(r"toolCount:\s*(\d+)", open("mod.js").read())
if m and int(m.group(1)) != len(declared):
    print(f"  FAIL mod.js metadata.toolCount={m.group(1)} but {len(declared)} tools declared"); fail = 1

if fail:
    sys.exit(1)

print(f"  OK  {len(declared)} tools agree across cartridge.json, mod.js and the FFI table")
PY

echo "parity: PASS"
