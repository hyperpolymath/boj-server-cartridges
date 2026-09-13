#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
#
# Foundry mint stage — scaffold a new cartridge from minter.toml.
#
# Delegates to tools/cartridge-minter/mint.js via Bun, then
# returns the scaffolded directory path on stdout.
#
# Usage: mint.sh <minter.toml>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
MINTER="$REPO_ROOT/tools/cartridge-minter/mint.js"

TOML="${1:-}"
if [[ -z "$TOML" || ! -f "$TOML" ]]; then
  echo "error: minter.toml not found: ${TOML:-<not provided>}" >&2
  exit 1
fi

TOML_ABS="$(cd "$(dirname "$TOML")" && pwd)/$(basename "$TOML")"

# The minter parses TOML once and emits the exact destination after success.
exec bun "$MINTER" "$TOML_ABS" --print-destination
