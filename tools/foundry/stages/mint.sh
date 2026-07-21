#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
#
# Foundry mint stage — scaffold a new cartridge from minter.toml.
#
# Delegates to tools/cartridge-minter/mint.ts via Deno, then
# returns the scaffolded directory path on stdout.
#
# Usage: mint.sh <minter.toml>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
MINTER="$REPO_ROOT/tools/cartridge-minter/mint.ts"

TOML="${1:-}"
if [[ -z "$TOML" || ! -f "$TOML" ]]; then
  echo "error: minter.toml not found: ${TOML:-<not provided>}" >&2
  exit 1
fi

TOML_ABS="$(cd "$(dirname "$TOML")" && pwd)/$(basename "$TOML")"

echo "==> mint: scaffolding from $TOML_ABS" >&2
# stdout of this script is a CONTRACT: it carries the scaffolded cartridge path
# and nothing else (foundry.sh consumes it). All minter chatter therefore goes to
# stderr — `2>&1` here would fold Deno's diagnostics into the path and corrupt it.
deno run \
  --allow-read \
  --allow-write \
  "$MINTER" \
  "$TOML_ABS" \
  >&2

# Derive the output path from the minter.toml (same logic as mint.ts)
NAME="$(grep '^name' "$TOML_ABS" | head -1 | sed 's/.*=\s*"\(.*\)"/\1/' | tr -d ' ')"
DOMAIN="$(grep '^domain' "$TOML_ABS" | head -1 | sed 's/.*=\s*"\(.*\)"/\1/' | tr -d ' ' | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//')"
CAT="$(grep '^category' "$TOML_ABS" | head -1 | sed 's/.*=\s*"\(.*\)"/\1/' | tr -d ' ' || echo "domain")"

if [[ "$CAT" == "cross-cutting" ]]; then
  SUBCAT="$(grep '^cross_cutting_category' "$TOML_ABS" | head -1 | sed 's/.*=\s*"\(.*\)"/\1/' | tr -d ' ' || echo "agentic")"
  echo "$REPO_ROOT/cartridges/cross-cutting/$SUBCAT/$NAME"
elif [[ "$CAT" == "template" ]]; then
  echo "$REPO_ROOT/cartridges/templates/$NAME"
else
  echo "$REPO_ROOT/cartridges/domains/$DOMAIN/$NAME"
fi
