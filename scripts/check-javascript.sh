#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
bun install --frozen-lockfile
(
  cd cartridges/domains/languages/orchestrator-lsp-mcp/panels
  bun install --frozen-lockfile
  bun run build
)
bun scripts/check-entrypoints.js
bun test tools cartridges "$@"
bun tools/validate-cartridges/main.js --strict
bun tools/build-catalog/main.js --check
