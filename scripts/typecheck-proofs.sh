#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# typecheck-proofs.sh — type-check EVERY Idris2 proof in this repo under the
# pinned toolchain (Idris2 0.8.0, see .tool-versions).
#
# WHY THIS EXISTS. boj-server-cartridges is the canonical cartridge home, but
# nothing ever ran `idris2` in CI here — only boj-server had a Proofs Gate. The
# two ABI proof trees therefore drifted: 23 cartridge proofs in this repo had
# silently rotted into non-compiling states (missing imports, a reserved-word
# field, an unprovable `Refl`, an exhausted `LTE` search, …) while their
# boj-server twins stayed green. This gate type-checks every cartridge ABI under
# cartridges/**/abi PLUS the Foundry design proof, so that divergence can never
# again pass unnoticed (issues #36 / #37).
#
# Each .idr is checked INDIVIDUALLY from its `abi/` root (module-relative path),
# which is the most thorough form: every module must compile on its own, not
# merely be listed in some possibly-stale .ipkg.
#
# Exit non-zero if anything fails to type-check (or times out).
set -uo pipefail
cd "$(dirname "$0")/.."

# A broken proof (e.g. an exhausted `LTE` auto-search) can make idris2 spin
# forever. Bound every check so the gate can't hang. Override with IDR_TIMEOUT.
TMO=${IDR_TIMEOUT:-120}
fail=0
pass=0

check_idr() { # abi_root  module_relative_path
    local out
    out=$(cd "$1" && timeout --kill-after=10 "$TMO" idris2 --check "$2" 2>&1)
    local rc=$?
    if [ $rc -eq 0 ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "  FAIL  $1/$2"
        [ $rc -eq 124 ] && echo "        TIMEOUT after ${TMO}s (proof search did not terminate)"
        printf '%s\n' "$out" | grep -vE '^[0-9]+/[0-9]+: Building' | head -6 | sed 's/^/        /'
    fi
}

echo "==> Cartridge ABIs (cartridges/**/abi)"
while IFS= read -r d; do
    while IFS= read -r f; do
        check_idr "$d" "${f#"$d"/}"
    done < <(find "$d" -name '*.idr' | sort)
done < <(find cartridges -type d -name abi | sort)

echo "==> Foundry design proof (tools/foundry/proof)"
if [ -f tools/foundry/proof/Foundry.idr ]; then
    check_idr tools/foundry/proof Foundry.idr
fi

echo "────────────────────────────────────────"
echo "Proof type-check: PASS=${pass} FAIL=${fail}"
[ "$fail" -eq 0 ] || { echo "PROOF TYPECHECK FAILED"; exit 1; }

# Vacuous-pass guard. PASS=0/FAIL=0 means the `find` matched nothing — a moved
# directory, a bad checkout, or a future refactor that renames `abi/`. Without
# this the gate reports success having verified NOTHING, which is precisely the
# failure mode this script was written to prevent. A repo with zero proofs is
# not a passing repo; it is a broken gate.
if [ "$pass" -eq 0 ]; then
    echo "PROOF TYPECHECK FAILED: no proofs were found to check." >&2
    echo "  Expected .idr files under cartridges/**/abi and/or tools/foundry/proof." >&2
    echo "  A green run with zero proofs verified would be a false assurance." >&2
    exit 1
fi

echo "All proofs type-check under the pinned toolchain."
