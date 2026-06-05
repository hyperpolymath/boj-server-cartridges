#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Typecheck the Foundry assurance model. Exit non-zero if the design proof —
# "no dropped proofs" + "least authority" — does not hold.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v idris2 >/dev/null 2>&1; then
  echo "idris2 not found — cannot check the Foundry design proof" >&2
  exit 127
fi

echo "== Foundry design proof =="
idris2 --check Foundry.idr
echo "OK — Foundry.idr typechecks:"
echo "   • no dropped proofs (sealing requires Complete; skip-harness rejected)"
echo "   • least authority (capability index = exact grant; never widened)"
rm -rf build 2>/dev/null || true
