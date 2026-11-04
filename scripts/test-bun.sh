#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# This is the existing Bun suite, not a Deno/pnpm compatibility claim.
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
panel="$repo_root/cartridges/domains/languages/orchestrator-lsp-mcp/panels"
cd -- "$panel"
# Frozen install must have its tracked input; Bun can otherwise install without
# writing a lock. No lifecycle scripts, metadata regeneration or global compiler.
test -f bun.lock
bun install --frozen-lockfile --ignore-scripts
test -x node_modules/.bin/rescript
bun run build
test -s lib/js/src/Extension.js

cd -- "$repo_root"
exec bun test tools cartridges
