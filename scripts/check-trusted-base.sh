#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# check-trusted-base.sh — enforce a ZERO-axiom trusted base for the cartridge
# proof tree.
#
# boj-server sanctions EXACTLY 5 class-(J) axioms (opaque Char/String primitives
# in src/abi/Boj/SafetyLemmas.idr). This repo is different: it holds only LEAF
# cartridge ABIs and the Foundry design proof, none of which may stand on an
# axiom — they must be genuinely constructive. So the sanctioned count here is 0.
#
# Fails on any believe_me / assert_total / assert_smaller / idris_crash / sorry
# in a .idr that is not inside a comment.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Scanning cartridge proofs for unsound constructs (must be axiom-free)..."
FOUND=$(grep -rn 'believe_me\|assert_total\|assert_smaller\|idris_crash\|\bsorry\b' \
        --include='*.idr' cartridges/ tools/ 2>/dev/null \
    | grep -v -- '--.*believe_me'   | grep -v '|||.*believe_me' \
    | grep -v -- '--.*assert_'      | grep -v '|||.*assert_' \
    | grep -v -- '--.*idris_crash'  | grep -v '|||.*idris_crash' \
    | grep -v -- '--.*sorry'        | grep -v '|||.*sorry' \
    | grep -vE ':[0-9]+:[[:space:]]*--' || true)
if [ -n "$FOUND" ]; then
    echo "CRITICAL: unsound constructs found in the cartridge proof tree:"
    echo "$FOUND"
    echo ""
    echo "Leaf cartridge proofs must be constructive. If a primitive is genuinely"
    echo "axiomatic, it belongs in boj-server's sanctioned SafetyLemmas module and"
    echo "the cartridge should depend on it — not restate the axiom here."
    exit 1
fi

echo "OK: cartridge proof tree is axiom-free (0 believe_me/assert/idris_crash/sorry)."
