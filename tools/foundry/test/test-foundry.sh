#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Tests for the Foundry Provision stage + the harness CapBounded check.
# Pure bash + jq (no deno/zig/idris required), so it runs anywhere CI has jq.
# Exits non-zero on any failure.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PROVISION="$HERE/../stages/provision.sh"
HARNESS="$HERE/../stages/harness.sh"

command -v jq >/dev/null 2>&1 || { echo "test-foundry: jq required" >&2; exit 3; }

pass=0; fail=0
ok(){   echo "  PASS ✓ $*"; pass=$((pass+1)); }
ko(){   echo "  FAIL ✗ $*"; fail=$((fail+1)); }
check(){ if eval "$2" >/dev/null 2>&1; then ok "$1"; else ko "$1"; fi; }
# check_fails: the command MUST exit non-zero
checkf(){ if eval "$2" >/dev/null 2>&1; then ko "$1 (expected failure)"; else ok "$1"; fi; }

newcart(){ # -> prints a fresh cartridge dir
  local d; d="$(mktemp -d)"; mkdir -p "$d/cart"
  echo '{"name":"demo-mcp","version":"0.1.0","tools":[]}' > "$d/cart/cartridge.json"
  echo "$d/cart"
}

echo "== Provision stage =="
C=$(newcart)
bash "$PROVISION" "$C" --granted "Fs, Net" >/dev/null
check "grant Fs,Net partitions correctly + inertness 0.6" \
  "jq -e '.capabilities|(.ephemeral|sort)==[\"Fs\",\"Net\"] and (.locked_down|sort)==[\"Clock\",\"Cred\",\"Rand\"] and .inertness==0.6' '$C/cartridge.json'"
check "preserves existing manifest keys" \
  "jq -e 'has(\"name\") and has(\"tools\") and has(\"version\")' '$C/cartridge.json'"
check "partition is complete (eph ∪ locked == universe)" \
  "jq -e '.capabilities|((.ephemeral+.locked_down)|sort)==(.universe|sort)' '$C/cartridge.json'"
check "partition is disjoint (eph ∩ locked == ∅)" \
  "jq -e '.capabilities|((.ephemeral-.locked_down)|length)==(.ephemeral|length)' '$C/cartridge.json'"
# Interior point that the Foundry.idr `grantFsLocksRest` proof pins by Refl.
bash "$PROVISION" "$C" --granted "Fs" >/dev/null
check "grant Fs -> locks {Net,Cred,Clock,Rand}, inertness 0.8 (matches Foundry.idr)" \
  "jq -e '.capabilities|(.ephemeral==[\"Fs\"]) and ((.locked_down|sort)==[\"Clock\",\"Cred\",\"Net\",\"Rand\"]) and .inertness==0.8' '$C/cartridge.json'"
bash "$PROVISION" "$C" --granted "" >/dev/null
check "grant nothing -> maximally inert (1.0, all 5 locked)" \
  "jq -e '.capabilities|.ephemeral==[] and (.locked_down|length==5) and .inertness==1' '$C/cartridge.json'"
checkf "rejects a capability outside the universe" \
  "bash '$PROVISION' '$C' --granted 'Bogus'"
checkf "requires --granted (refuses to guess)" \
  "bash '$PROVISION' '$C'"
bash "$PROVISION" "$C" --granted "Fs" >/dev/null; A=$(jq -cS .capabilities "$C/cartridge.json")
bash "$PROVISION" "$C" --granted "Fs" >/dev/null; B=$(jq -cS .capabilities "$C/cartridge.json")
check "idempotent (re-provision same grant == identical)" "[ '$A' = '$B' ]"
rm -rf "$(dirname "$C")"

echo "== Harness · CapBounded =="
# A provisioned cartridge with no abi/ffi and available=false: only CapBounded is
# substantive; ABI/FFI/Truthful skip or pass, so harness exit reflects CapBounded.
C=$(newcart)
bash "$PROVISION" "$C" --granted "Fs" >/dev/null
check "harness PASSES a valid partition with matching grant" \
  "bash '$HARNESS' '$C' --granted 'Fs,Net'"
# Escalation: manifest claims Net but only Fs was granted to the harness.
bash "$PROVISION" "$C" --granted "Fs,Net" >/dev/null
checkf "harness FAILS when manifest grant exceeds the supplied grant (escalation)" \
  "bash '$HARNESS' '$C' --granted 'Fs'"
# Tampered partition: locked_down drops a member so eph ∪ locked != universe.
jq '.capabilities.locked_down = ["Cred"]' "$C/cartridge.json" > "$C/t" && mv "$C/t" "$C/cartridge.json"
checkf "harness FAILS a tampered (incomplete) partition" \
  "bash '$HARNESS' '$C' --granted 'Fs,Net'"
rm -rf "$(dirname "$C")"

echo "──────────────────────────────"
echo "test-foundry: PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] || exit 1
echo "All Foundry provision/harness tests pass."
