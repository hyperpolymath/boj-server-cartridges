#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Every native build root, including adapters whose main() test-only builds omit.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
ZIG="${ZIG:-zig}"
[[ "$($ZIG version)" == 0.16.0 ]] || { echo 'Zig 0.16.0 is required' >&2; exit 2; }
count=0
while IFS= read -r -d '' build; do
  dir="${build%/build.zig}"
  echo "Native build/test/install: $dir"
  (cd "$dir"; "$ZIG" build test "$@"; "$ZIG" build "$@")
  count=$((count + 1))
done < <(find cartridges -type f -name build.zig -not -path '*/.zig-cache/*' -print0 | sort -z)
(( count > 0 )) || { echo 'No native build roots found' >&2; exit 2; }
echo "$count native build/test/install roots passed"
