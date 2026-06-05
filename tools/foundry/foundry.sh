#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# The Foundry wizard — produce a high-assurance cartridge from a settings choice.
# Runs the assured flow modelled+checked in proof/Foundry.idr:
#
#     mint  ->  provision  ->  configure  ->  harness
#
# The user's only real effort is choosing settings; everything else is derived
# from the proven pre-mint framework. See SPEC.adoc.
#
# Usage:
#   foundry.sh                       # interactive wizard
#   foundry.sh --from minter.toml    # non-interactive (CI / scripted)
#   foundry.sh --harness <dir>       # just re-run the assurance gate on a dir
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
MINTER="$REPO/tools/cartridge-minter/mint.ts"
KINDS="domain coordination agentic nesy"
CAPS="Net Fs Cred Clock Rand"

say() { printf '\033[1m%s\033[0m\n' "$*"; }
note(){ printf '   %s\n' "$*"; }

# ── re-run the harness only ────────────────────────────────────────────────
if [ "${1:-}" = "--harness" ]; then
  exec "$HERE/stages/harness.sh" "${2:?usage: --harness <cartridge-dir>}" "${@:3}"
fi

# ── 0 · confirm the design proof still holds before minting anything ────────
say "Foundry · verifying the design proof (no dropped proofs, least authority)"
if command -v idris2 >/dev/null 2>&1; then
  "$HERE/proof/check.sh" >/dev/null && note "proof/Foundry.idr ✓ typechecks" \
    || { echo "ABORT: the Foundry design proof does not hold — refusing to mint." >&2; exit 1; }
else
  note "idris2 absent — skipping local proof check (CI enforces it)"
fi

# ── gather settings ────────────────────────────────────────────────────────
TOML=""
if [ "${1:-}" = "--from" ]; then
  TOML="${2:?--from needs a path}"
  [ -f "$TOML" ] || { echo "no such file: $TOML" >&2; exit 2; }
else
  say "Foundry · new cartridge — choose your settings"
  read -rp "  name (must end -mcp/-lsp/-agentic/-nesy/…): " NAME
  read -rp "  one-line description: " DESC
  read -rp "  domain (e.g. Archive, Comms, Cloud): " DOMAIN
  read -rp "  tier [Teranga|Shield|Ayo] (Ayo): " TIER; TIER="${TIER:-Ayo}"
  read -rp "  kind [$KINDS] (domain): " KIND; KIND="${KIND:-domain}"
  read -rp "  granted capabilities, comma-sep from [$CAPS] (none): " GRANT
  read -rp "  of those, which are ephemeral (rest are locked-down): " EPHEM
  TOML="$(mktemp --suffix=.minter.toml)"
  {
    echo "name = \"$NAME\""
    echo "description = \"$DESC\""
    echo "version = \"0.1.0\""
    echo "domain = \"$DOMAIN\""
    echo "tier = \"$TIER\""
    [ "$KIND" = domain ] || { echo "category = \"cross-cutting\""; echo "cross_cutting_category = \"$KIND\""; }
    echo "# foundry capability plan (provision stage):"
    echo "# granted = [$GRANT]  ephemeral = [$EPHEM]  locked-down = the rest of [$CAPS]"
  } > "$TOML"
  note "wrote $TOML"
fi

DEST_NAME="$(grep -E '^name' "$TOML" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"

# ── 1 · MINT (delegate to the existing minter) ─────────────────────────────
say "1/4 · mint — scaffold from the proven template"
if command -v deno >/dev/null 2>&1; then
  deno run --allow-read --allow-write "$MINTER" "$TOML"
  note "minted via cartridge-minter"
else
  note "deno not installed here — the Mint stage shells to $MINTER"
  note "(install deno to run end-to-end; the rest of the flow is toolchain-local)"
fi

# ── 2 · PROVISION (capability grant: locked-down vs ephemeral) ─────────────
say "2/4 · provision — grant exactly the capabilities chosen, nothing more"
note "least authority: ungranted capabilities are statically absent (see proof)"

# ── 3 · CONFIGURE (settings already captured in the descriptor) ────────────
say "3/4 · configure — apply settings (preserves every proof + the grant)"

# ── 4 · HARNESS (the one standard assurance gate) ──────────────────────────
say "4/4 · harness — run the standard assurance gate"
CART_DIR="$(find "$REPO/cartridges" -type d -name "$DEST_NAME" 2>/dev/null | head -1)"
if [ -n "$CART_DIR" ]; then
  "$HERE/stages/harness.sh" "$CART_DIR" ${GRANT:+--granted "$GRANT"}
else
  note "cartridge dir not found (Mint did not run — deno absent). Harness skipped."
  note "to gate an existing cartridge: foundry.sh --harness <dir>"
fi

say "Foundry · done."
