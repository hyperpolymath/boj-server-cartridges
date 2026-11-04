#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
# Exercise the actual stamp/check script in a disposable cartridge tree.
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture/tools" "$fixture/cartridges/templates/gossamer-mcp/ffi" \
  "$fixture/cartridges/domains/gaming/npc-mcp/ffi"
cp "$repo/tools/sync_cartridge_shim.sh" "$fixture/tools/"
canon="$fixture/cartridges/templates/gossamer-mcp/ffi/cartridge_shim.zig"
copy="$fixture/cartridges/domains/gaming/npc-mcp/ffi/cartridge_shim.zig"
cat > "$canon" <<'ZIG'
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
// The implementation and this comment must match.
pub const RC_SUCCESS: i32 = 0;
// Copyright (c) 2026 Body fixture: this later comment is compared.
ZIG

reset_copy() {
  sed '2c\// SPDX-FileCopyrightText: 2026 Joshua Benjamin Jewell <developer@joshuajewell.dev>' "$canon" > "$copy"
}
checks=0
expect_exit() {
  local expected=$1 actual=0
  shift
  bash "$fixture/tools/sync_cartridge_shim.sh" "$@" > "$fixture/result.log" 2>&1 || actual=$?
  if [ "$actual" -ne "$expected" ]; then
    cat "$fixture/result.log" >&2
    printf 'Expected exit %s, got %s for %s\n' "$expected" "$actual" "$*" >&2
    exit 1
  fi
  checks=$((checks + 1))
}
assert_joshua() {
  grep -Fxq '// SPDX-FileCopyrightText: 2026 Joshua Benjamin Jewell <developer@joshuajewell.dev>' "$copy"
  if grep -q 'Jonathan D.A. Jewell' "$copy"; then
    echo 'Stamp replaced destination copyright with template attribution' >&2
    exit 1
  fi
}

# Attribution alone is not implementation drift and must never be restamped.
reset_copy
cp "$copy" "$fixture/before"
expect_exit 0 --check
expect_exit 0
cmp "$fixture/before" "$copy"
assert_joshua

# Multiple explicit notices survive an actual code refresh byte for byte.
sed -i '3i\// Copyright (c) 2025 Another contributor' "$copy"
expect_exit 0 --check
sed -i 's/RC_SUCCESS: i32 = 0/RC_SUCCESS: i32 = 7/' "$copy"
expect_exit 1 --check
expect_exit 0 stamp
assert_joshua
grep -Fxq '// Copyright (c) 2025 Another contributor' "$copy"
grep -Fxq 'pub const RC_SUCCESS: i32 = 0;' "$copy"
expect_exit 0 --check

# A licence change requires owner review; stamping may never relicense a copy.
sed -i 's/SPDX-License-Identifier: MPL-2.0/SPDX-License-Identifier: Apache-2.0/' "$copy"
cp "$copy" "$fixture/different-licence"
expect_exit 1 --check
expect_exit 2 stamp
cmp "$fixture/different-licence" "$copy"
grep -Fxq '// SPDX-License-Identifier: Apache-2.0' "$copy"
assert_joshua
reset_copy
expect_exit 0 --check
sed -i '/SPDX-License-Identifier:/d' "$copy"
cp "$copy" "$fixture/missing-licence"
expect_exit 1 --check
expect_exit 2 stamp
cmp "$fixture/missing-licence" "$copy"

# Neither unrelated header prose nor a notice-shaped comment after code is
# exempt. The final-newline check guards byte fidelity in the normalizer.
reset_copy
sed -i 's/this comment must match/this comment drifted/' "$copy"
expect_exit 1 --check
reset_copy
sed -i 's/Body fixture:/Changed body fixture:/' "$copy"
expect_exit 1 --check
reset_copy
truncate -s -1 "$copy"
expect_exit 1 --check

# Missing attribution cannot be reconstructed from the template author.
reset_copy
sed -i '2d' "$copy"
cp "$copy" "$fixture/missing-notice"
expect_exit 1 --check
expect_exit 2 stamp
cmp "$fixture/missing-notice" "$copy"

# A mistyped check must not fall into the mutating default mode.
reset_copy
sed -i 's/RC_SUCCESS: i32 = 0/RC_SUCCESS: i32 = 9/' "$copy"
cp "$copy" "$fixture/invalid-mode"
expect_exit 2 --chekc
cmp "$fixture/invalid-mode" "$copy"
printf '%s shim synchronization controls passed\n' "$checks"
