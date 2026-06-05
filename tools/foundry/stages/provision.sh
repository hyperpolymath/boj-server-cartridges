#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# The Provision stage — grant an EXACT capability set and record it in the
# cartridge manifest, so the harness can enforce least authority (CapBounded).
#
# Capability model (matches SPEC.adoc + the Foundry design proof). The framework
# fixes a finite capability UNIVERSE. Under fork-per-request (ADR-0005) a
# cartridge keeps no cross-invocation state, so every granted capability is
# necessarily scoped to a single fork — i.e. EPHEMERAL. The disposition of each
# capability is therefore BINARY:
#
#   * ephemeral   — granted; live only for one fork-per-request invocation.
#   * locked_down — denied; provably absent (universe \ ephemeral).
#
# Provisioning writes a `capabilities` block that PARTITIONS the universe:
#
#   ephemeral ∪ locked_down = universe        (completeness — every cap classified)
#   ephemeral ∩ locked_down = ∅               (consistency — none both granted+denied)
#
# `inertness` = |locked_down| / |universe| is the obleeny metric: 1.0 means the
# cartridge is granted nothing (maximally inert); the Foundry pushes it as high
# as the chosen settings allow.
#
# Usage:
#   provision.sh <cartridge-dir> --granted "Fs,Net" [--universe "Net,Fs,Cred,Clock,Rand"]
#   provision.sh <cartridge-dir> --granted ""        # grant nothing — maximally inert
set -euo pipefail

CART="${1:?usage: provision.sh <cartridge-dir> --granted \"Fs,Net\" [--universe ...]}"
shift || true

GRANTED=""
UNIVERSE_CSV="Net,Fs,Cred,Clock,Rand"   # framework-fixed default (== foundry.sh CAPS == Foundry.idr Capability)
GRANTED_SET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --granted)  GRANTED="${2-}"; GRANTED_SET=1; shift 2 ;;
    --universe) UNIVERSE_CSV="${2:?}"; shift 2 ;;
    *) echo "provision: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ "$GRANTED_SET" = 1 ] || { echo "provision: --granted is required (use --granted \"\" to grant nothing)" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || { echo "provision: jq is required" >&2; exit 3; }
CJ="$CART/cartridge.json"
[ -f "$CJ" ] || { echo "provision: no cartridge.json at $CART" >&2; exit 2; }

# CSV -> JSON array (strip whitespace, drop blanks, de-duplicate). Done entirely
# in jq so the empty string yields [] cleanly (no grep, whose exit-1-on-no-match
# would trip `set -e`/pipefail).
csv_to_json() { # csv
  jq -cn --arg s "$1" '$s | split(",") | map(gsub("\\s";"")) | map(select(length>0)) | unique'
}
UNI_JSON=$(csv_to_json "$UNIVERSE_CSV")
GRANT_JSON=$(csv_to_json "$GRANTED")

# Validate: every granted capability must be in the universe (no inventing caps).
BAD=$(jq -rn --argjson u "$UNI_JSON" --argjson g "$GRANT_JSON" '($g - $u) | join(", ")')
if [ -n "$BAD" ]; then
  echo "provision: capabilities not in universe [$UNIVERSE_CSV]: $BAD" >&2
  exit 1
fi

# Build the partition. ephemeral = grant; locked_down = universe \ grant.
CAPS_JSON=$(jq -n --argjson u "$UNI_JSON" --argjson g "$GRANT_JSON" '
  ($g | unique)        as $eph |
  ($u - $eph)          as $locked |
  {
    universe:    $u,
    ephemeral:   $eph,
    locked_down: $locked,
    inertness:   (($locked | length) / ($u | length))
  }')

# Assert the partition invariants BEFORE writing (defence in depth).
jq -e -n --argjson c "$CAPS_JSON" '
  ( ($c.ephemeral + $c.locked_down) | sort ) == ( $c.universe | sort )      # completeness
  and (($c.ephemeral - $c.locked_down) | length) == ($c.ephemeral | length) # disjoint
' >/dev/null || { echo "provision: INTERNAL — partition invariants violated, refusing to write" >&2; exit 4; }

# Inject (or replace) the capabilities block; keep the rest of the manifest intact.
tmp=$(mktemp)
jq --argjson c "$CAPS_JSON" '.capabilities = $c' "$CJ" > "$tmp" && mv "$tmp" "$CJ"

eph=$(jq -r '.capabilities.ephemeral | join(", ") | if . == "" then "(none)" else . end' "$CJ")
lck=$(jq -r '.capabilities.locked_down | join(", ") | if . == "" then "(none)" else . end' "$CJ")
inert=$(jq -r '.capabilities.inertness' "$CJ")
echo "provision: $(basename "$CART")"
echo "  ephemeral (granted) : $eph"
echo "  locked-down (denied): $lck"
echo "  inertness           : $inert"
