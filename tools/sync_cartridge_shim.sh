#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# sync_cartridge_shim.sh — keep shim implementation and licence bytes identical
# to the canonical template while retaining each copy's copyright notices.
#
# The shim is deliberately vendored into each cartridge's ffi/ (file-relative
# @import, no build-graph coupling), which makes drift the failure mode. This
# script is the single mechanism for both directions:
#
#   tools/sync_cartridge_shim.sh          # stamp: refresh code, preserve attribution
#   tools/sync_cartridge_shim.sh --check  # CI gate: fail if any copy drifts
#
# Canonical source: cartridges/templates/gossamer-mcp/ffi/cartridge_shim.zig
# (fixing the template is what stops new mints regressing).
# NPC's Joshua Benjamin Jewell notice (PR #162) is a permitted attribution
# difference, not implementation drift. The shim-drift CI job runs this check
# and test_sync_cartridge_shim.sh's preservation/body/licence controls.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

CANON="cartridges/templates/gossamer-mcp/ffi/cartridge_shim.zig"
[ -f "$CANON" ] || { echo "ERROR: canonical shim not found at $CANON" >&2; exit 2; }

mode="${1:-stamp}"
if [ "$#" -gt 1 ] || { [ "$mode" != stamp ] && [ "$mode" != --check ]; }; then
  echo "usage: $0 [stamp|--check]" >&2
  exit 2
fi

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
# Only explicit full-line notices in the leading comment block may vary.
# SPDX-License-Identifier, other comments, and every byte after code begins
# remain part of the comparison. This also prevents an executable string or
# a later comment containing the word Copyright from becoming an exemption.
notice_re='^[[:space:]]*//[[:space:]]+(SPDX-FileCopyrightText:[[:space:]]+.+|Copyright[[:space:]]+(\(c\)[[:space:]]+)?[0-9]{4}.*)$'

without_notices() {
  sed -E "
    :header
    \\~$notice_re~d
    \\~^[[:space:]]*(//.*)?$~b
    :body
    n
    b body
  " "$1"
}

notices() {
  sed -nE "
    \\~$notice_re~p
    \\~^[[:space:]]*(//.*)?$~b
    q
  " "$1"
}

licence_notices() {
  sed -nE '
    \~^[[:space:]]*//[[:space:]]+SPDX-License-Identifier:~p
    \~^[[:space:]]*(//.*)?$~b
    q
  ' "$1"
}

without_notices "$CANON" > "$work/canonical"
notices "$CANON" > "$work/canonical-notices"
[ -s "$work/canonical-notices" ] || { echo "ERROR: canonical shim has no copyright notice" >&2; exit 2; }
licence_notices "$CANON" > "$work/canonical-licence"
[ -s "$work/canonical-licence" ] || { echo "ERROR: canonical shim has no licence declaration" >&2; exit 2; }
notice_line=$(grep -n -m1 -E "$notice_re" "$CANON" | cut -d: -f1)

drift=0
stamped=0
total=0
while IFS= read -r -d '' copy; do
  [ "$copy" = "$CANON" ] && continue
  total=$((total + 1))
  without_notices "$copy" > "$work/copy"
  notices "$copy" > "$work/copy-notices"
  if [ ! -s "$work/copy-notices" ]; then
    echo "DRIFT: $copy has no copyright notice; attribution cannot be inferred" >&2
    drift=$((drift + 1))
    continue
  fi
  licence_notices "$copy" > "$work/copy-licence"
  if ! cmp -s "$work/copy-licence" "$work/canonical-licence"; then
    echo "DRIFT: $copy has a differing or missing licence declaration; owner review required, no automatic relicensing" >&2
    drift=$((drift + 1))
    continue
  fi
  if ! cmp -s "$work/copy" "$work/canonical"; then
    if [ "$mode" = "--check" ]; then
      echo "DRIFT: $copy" >&2
      drift=$((drift + 1))
    else
      # Insert the destination's exact notice lines at the canonical notice
      # position; never assign the template author's name to another author.
      if [ "$notice_line" -eq 1 ]; then
        cat "$work/copy-notices" "$work/canonical" > "$work/stamped"
      else
        sed "$((notice_line - 1))r $work/copy-notices" "$work/canonical" > "$work/stamped"
      fi
      without_notices "$work/stamped" > "$work/stamped-body"
      notices "$work/stamped" > "$work/stamped-notices"
      cmp -s "$work/stamped-body" "$work/canonical"
      cmp -s "$work/stamped-notices" "$work/copy-notices"
      cat "$work/stamped" > "$copy"
      stamped=$((stamped + 1))
    fi
  fi
done < <(find cartridges -name 'cartridge_shim.zig' -not -path '*/.claude/*' -not -path '*/zig-out/*' -not -path '*/.zig-cache/*' -print0 | sort -z)

if [ "$mode" = "--check" ]; then
  echo "checked $total copies against $CANON: $drift drifted"
  [ "$drift" -eq 0 ] || exit 1
else
  echo "stamped $stamped of $total copies from $CANON"
  [ "$drift" -eq 0 ] || exit 2
fi
