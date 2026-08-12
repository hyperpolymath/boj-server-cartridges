#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# sync_cartridge_shim.sh — keep every vendored cartridge_shim.zig byte-identical
# to the canonical template copy.
#
# The shim is deliberately vendored into each cartridge's ffi/ (file-relative
# @import, no build-graph coupling), which makes drift the failure mode. This
# script is the single mechanism for both directions:
#
#   tools/sync_cartridge_shim.sh          # stamp: overwrite every copy from canon
#   tools/sync_cartridge_shim.sh --check  # CI gate: fail if any copy drifts
#
# Canonical source: cartridges/templates/gossamer-mcp/ffi/cartridge_shim.zig
# (fixing the template is what stops new mints regressing).

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

CANON="cartridges/templates/gossamer-mcp/ffi/cartridge_shim.zig"
[ -f "$CANON" ] || { echo "ERROR: canonical shim not found at $CANON" >&2; exit 2; }

mode="${1:-stamp}"
canon_sum="$(md5sum "$CANON" | cut -d' ' -f1)"

drift=0
stamped=0
total=0
while IFS= read -r copy; do
  [ "$copy" = "$CANON" ] && continue
  total=$((total + 1))
  sum="$(md5sum "$copy" | cut -d' ' -f1)"
  if [ "$sum" != "$canon_sum" ]; then
    if [ "$mode" = "--check" ]; then
      echo "DRIFT: $copy" >&2
      drift=$((drift + 1))
    else
      cp "$CANON" "$copy"
      stamped=$((stamped + 1))
    fi
  fi
done < <(find cartridges -name 'cartridge_shim.zig' -not -path '*/.claude/*' -not -path '*/zig-out/*' -not -path '*/.zig-cache/*' | sort)

if [ "$mode" = "--check" ]; then
  echo "checked $total copies against $CANON: $drift drifted"
  [ "$drift" -eq 0 ] || exit 1
else
  echo "stamped $stamped of $total copies from $CANON"
fi
