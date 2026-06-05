#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# The general harness — ONE standard assurance gate for every cartridge,
# whatever its kind. It discharges, concretely, the obligations the Foundry
# design proof (proof/Foundry.idr) models in types:
#
#   AbiConform + MemSafe : every abi/*.idr typechecks AND the FFI builds against
#                          the shared cartridge_shim.zig
#   Truthful             : if available:true, invoking the first tool returns a
#                          non-stub result (the boj-server #196 gate, inlined)
#   CapBounded           : declared capabilities are a subset of the grant
#
# Usage: harness.sh <cartridge-dir> [--granted "Net,Fs,..."]
set -euo pipefail

CART="${1:?usage: harness.sh <cartridge-dir> [--granted caps]}"
shift || true
GRANTED=""
[ "${1:-}" = "--granted" ] && { GRANTED="${2:-}"; }

[ -d "$CART" ] || { echo "harness: no such cartridge: $CART" >&2; exit 2; }
CJ="$CART/cartridge.json"

fail=0
ok()  { printf '  ok   %s\n' "$*"; }
bad() { printf '  FAIL %s\n' "$*" >&2; fail=1; }
skip(){ printf '  --   %s\n' "$*"; }

name=$( [ -f "$CJ" ] && command -v jq >/dev/null 2>&1 && jq -r '.name // "?"' "$CJ" || basename "$CART" )
echo "== harness: $name =="

# 1 ─ AbiConform: typecheck every ABI proof (module path is relative to abi/).
abidir="$CART/abi"
if command -v idris2 >/dev/null 2>&1 && [ -d "$abidir" ]; then
  found=0
  while IFS= read -r idr; do
    found=1; rel="${idr#"$abidir"/}"
    if (cd "$abidir" && idris2 --check "$rel") >/dev/null 2>&1; then ok "proof $rel"; else bad "proof failed: $rel"; fi
  done < <(find "$abidir" -name '*.idr' 2>/dev/null)
  [ "$found" = 1 ] || skip "no abi/*.idr to check"
  rm -rf "$abidir"/build 2>/dev/null || true
else
  skip "idris2 / abi unavailable — ABI proofs not checked here (CI does)"
fi

# 2 ─ MemSafe: the FFI must build against the shared shim.
if command -v zig >/dev/null 2>&1 && [ -f "$CART/ffi/build.zig" ]; then
  if (cd "$CART/ffi" && zig build) >/dev/null 2>&1; then ok "ffi builds (shim-conformant)"; else bad "zig build failed"; fi
  rm -rf "$CART/ffi/zig-out" "$CART/ffi/.zig-cache" 2>/dev/null || true
else
  skip "zig / build.zig unavailable — FFI not built here (CI does)"
fi

# 3 ─ Truthful: only advertised cartridges must prove non-stub.
avail=$( [ -f "$CJ" ] && command -v jq >/dev/null 2>&1 && jq -r '.available // false' "$CJ" || echo false )
if [ "$avail" = "true" ]; then
  so_rel=$( jq -r '.ffi.so_path // empty' "$CJ" )
  tool=$( jq -r '.tools[0].name // empty' "$CJ" )
  inv=$(command -v boj-invoke || echo "../boj-server/ffi/zig/zig-out/bin/boj-invoke")
  if [ -n "$so_rel" ] && [ -x "$inv" ] && [ -n "$tool" ]; then
    out=$("$inv" "$CART/$so_rel" invoke "$tool" '{}' 2>/dev/null || true)
    if [ -z "$out" ]; then bad "available but '$tool' gave no output"
    elif printf '%s' "$out" | grep -qE '"status"[[:space:]]*:[[:space:]]*"stub"'; then bad "available but '$tool' is a stub: $out"
    else ok "truthful: $tool -> ${out:0:48}"; fi
  else
    skip "available:true but cannot probe here (needs boj-invoke + built .so)"
  fi
else
  ok "truthful: available=false (correctly not advertised — nothing to over-claim)"
fi

# 4 ─ CapBounded: the `capabilities` block (written by the Provision stage) must
#     be a valid PARTITION of the universe, and must not claim more capability
#     than was granted. This is the value-level counterpart of the type-level
#     CapBounded proven in proof/Foundry.idr.
if [ -f "$CJ" ] && command -v jq >/dev/null 2>&1; then
  if jq -e '(.capabilities? | type) == "object"' "$CJ" >/dev/null 2>&1; then
    # 4a · partition invariants: ephemeral ∪ locked_down = universe (complete)
    #      and ephemeral ∩ locked_down = ∅ (disjoint).
    if jq -e '.capabilities as $c
              | (($c.ephemeral + $c.locked_down) | sort) == ($c.universe | sort)
                and (($c.ephemeral - $c.locked_down) | length) == ($c.ephemeral | length)' \
              "$CJ" >/dev/null 2>&1; then
      inert=$(jq -r '.capabilities.inertness // "?"' "$CJ")
      eph=$(jq -r '.capabilities.ephemeral | join(",")' "$CJ")
      ok "cap-bounded: valid partition (granted [${eph:-none}], inertness ${inert})"
    else
      bad "capabilities block is not a valid partition of the universe"
    fi
    # 4b · if a grant was supplied, the manifest must not exceed it.
    if [ -n "$GRANTED" ]; then
      gj=$(printf '%s' "$GRANTED" | jq -cR 'split(",") | map(gsub("\\s";"")) | map(select(length>0))')
      over=$(jq -rn --argjson g "$gj" --slurpfile cj "$CJ" '($cj[0].capabilities.ephemeral - $g) | join(", ")')
      [ -z "$over" ] && ok "manifest grant ⊆ provisioned grant [$GRANTED]" \
                     || bad "capability escalation: $over not in grant [$GRANTED]"
    fi
  else
    skip "no capabilities block — run the Provision stage (foundry.sh) to add one"
  fi
fi

echo "---"
if [ "$fail" = 0 ]; then echo "harness: PASS ($name)"; else echo "harness: FAIL ($name)"; fi
exit "$fail"
