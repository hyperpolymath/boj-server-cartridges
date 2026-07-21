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
# FAIL-CLOSED (--strict). The wizard's value is the assurance it carries, so a
# missing toolchain must not silently degrade it. In strict mode an absent
# deno/idris2/jq is a FAILURE, not a skip. Without --strict the wizard is
# permissive for local exploration, but it will still never claim success for a
# cartridge it did not actually produce.
#
# Usage:
#   foundry.sh                       # interactive wizard
#   foundry.sh --from minter.toml    # non-interactive (CI / scripted)
#   foundry.sh --strict --from f.toml# fail on any missing toolchain (use in CI)
#   foundry.sh --harness <dir>       # just re-run the assurance gate on a dir
#
# Env: FOUNDRY_STRICT=1 is equivalent to passing --strict.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
KINDS="domain coordination agentic nesy"
CAPS="Net Fs Cred Clock Rand"

say() { printf '\033[1m%s\033[0m\n' "$*"; }
note(){ printf '   %s\n' "$*"; }

STRICT="${FOUNDRY_STRICT:-0}"

# need <tool> <why> — in strict mode a missing tool aborts; otherwise it reports
# the degradation and returns 1 so the caller can branch.
need() {
  if command -v "$1" >/dev/null 2>&1; then return 0; fi
  if [ "$STRICT" = 1 ]; then
    echo "ABORT (--strict): '$1' is required — $2" >&2
    exit 1
  fi
  note "$1 absent — $2 (re-run with --strict to make this an error)"
  return 1
}

# ── argument pre-pass: --strict may appear anywhere ────────────────────────
ARGS=()
for a in "$@"; do
  case "$a" in
    --strict) STRICT=1 ;;
    *) ARGS+=("$a") ;;
  esac
done
set -- ${ARGS[@]+"${ARGS[@]}"}

# ── re-run the harness only ────────────────────────────────────────────────
if [ "${1:-}" = "--harness" ]; then
  exec "$HERE/stages/harness.sh" "${2:?usage: --harness <cartridge-dir>}" "${@:3}"
fi

# ── 0 · confirm the design proof still holds before minting anything ────────
say "Foundry · verifying the design proof (no dropped proofs, least authority)"
if need idris2 "the Foundry design proof cannot be checked locally"; then
  "$HERE/proof/check.sh" >/dev/null && note "proof/Foundry.idr ✓ typechecks" \
    || { echo "ABORT: the Foundry design proof does not hold — refusing to mint." >&2; exit 1; }
fi

# ── gather settings ────────────────────────────────────────────────────────
TOML=""
API_BASE=""; AUTH_METHOD=""; AUTH_ENV=""
if [ "${1:-}" = "--from" ]; then
  TOML="${2:?--from needs a path}"
  [ -f "$TOML" ] || { echo "no such file: $TOML" >&2; exit 2; }
else
  say "Foundry · new cartridge — choose your settings"
  read -rp "  name (must end -mcp/-lsp/-agentic/-nesy/…): " NAME
  read -rp "  one-line description: " DESC
  read -rp "  domain (e.g. Archive, Comms, Cloud): " DOMAIN
  read -rp "  tier [Teranga|Shield|Ayo] (Ayo): " TIER; TIER="${TIER:-Ayo}"
  # `protocols` is REQUIRED by the minter's validator. The wizard used to omit
  # it, so every interactively-produced descriptor was rejected at Mint.
  read -rp "  protocols, comma-sep [mcp|rest|grpc|graphql|lsp|dap|bsp] (mcp): " PROTOCOLS
  PROTOCOLS="${PROTOCOLS:-mcp}"
  read -rp "  kind [$KINDS] (domain): " KIND; KIND="${KIND:-domain}"
  read -rp "  granted capabilities, comma-sep from [$CAPS] (blank = none, maximally inert): " GRANT
  note "fork-per-request (ADR-0005) ⇒ every grant is ephemeral; ungranted caps are locked-down/denied"
  read -rp "  backend base_url (blank = local://<name> loopback): " API_BASE
  read -rp "  auth method [none|api-key|oauth2|vault] (none): " AUTH_METHOD
  AUTH_METHOD="${AUTH_METHOD:-none}"
  [ "$AUTH_METHOD" = none ] || read -rp "  auth env var (e.g. EXAMPLE_TOKEN): " AUTH_ENV
  TOML="$(mktemp --suffix=.minter.toml)"
  {
    echo "name = \"$NAME\""
    echo "description = \"$DESC\""
    echo "version = \"0.1.0\""
    echo "domain = \"$DOMAIN\""
    echo "tier = \"$TIER\""
    # CSV -> TOML array of strings, e.g. `mcp,rest` -> ["mcp", "rest"].
    echo "protocols = [$(printf '%s' "$PROTOCOLS" | tr ',' '\n' \
      | sed -E 's/^[[:space:]]+|[[:space:]]+$//g; /^$/d; s/^/"/; s/$/"/' \
      | paste -sd, -)]"
    [ "$KIND" = domain ] || { echo "category = \"cross-cutting\""; echo "cross_cutting_category = \"$KIND\""; }
    # Capability plan consumed by the Provision stage (provision.sh --granted).
    echo "granted = \"$GRANT\""
    # Settings consumed by the Configure stage (configure.sh).
    [ -n "$API_BASE" ]    && echo "api_base = \"$API_BASE\""
    [ "$AUTH_METHOD" != none ] && echo "auth_method = \"$AUTH_METHOD\""
    [ -n "$AUTH_ENV" ]    && echo "auth_env = \"$AUTH_ENV\""
  } > "$TOML"
  note "wrote $TOML"
fi

# Read any settings that live in the descriptor (both --from and interactive).
toml_get() { sed -nE "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"([^\"]*)\".*/\1/p" "$TOML" | head -1; }
: "${GRANT:=}"
[ -n "$GRANT" ]       || GRANT="$(toml_get granted)"
[ -n "$API_BASE" ]    || API_BASE="$(toml_get api_base)"
[ -n "$AUTH_METHOD" ] || AUTH_METHOD="$(toml_get auth_method)"
[ -n "$AUTH_ENV" ]    || AUTH_ENV="$(toml_get auth_env)"

# ── 1 · MINT (delegate to the Mint stage — single source of path logic) ────
say "1/4 · mint — scaffold from the proven template"
CART_DIR=""
if need deno "the Mint stage cannot scaffold a cartridge"; then
  # mint.sh's stdout is the scaffolded path; its chatter goes to stderr.
  CART_DIR="$("$HERE/stages/mint.sh" "$TOML")"
  [ -n "$CART_DIR" ] && [ -d "$CART_DIR" ] \
    || { echo "ABORT: Mint reported '$CART_DIR' but no such directory exists." >&2; exit 1; }
  note "minted -> $CART_DIR"
fi

# Without a minted directory the remaining stages have nothing to act on. Say so
# plainly and exit non-zero: the wizard must never report success for a
# cartridge it did not produce.
if [ -z "$CART_DIR" ]; then
  echo "Foundry: INCOMPLETE — no cartridge was minted, so provision/configure/harness did not run." >&2
  echo "         Install deno and re-run, or gate an existing cartridge with: foundry.sh --harness <dir>" >&2
  exit 1
fi

# ── 2 · PROVISION (grant exactly the chosen caps; record the partition) ────
say "2/4 · provision — grant exactly the capabilities chosen, nothing more"
"$HERE/stages/provision.sh" "$CART_DIR" --granted "$GRANT"
note "least authority: ungranted capabilities are locked-down (provably absent — see proof)"

# ── 3 · CONFIGURE (apply settings; cannot drop a proof or widen the grant) ──
say "3/4 · configure — apply settings (preserves every proof + the grant)"
CFG_ARGS=()
[ -n "$API_BASE" ]                              && CFG_ARGS+=(--api-base "$API_BASE")
[ -n "$AUTH_METHOD" ] && [ "$AUTH_METHOD" != none ] && CFG_ARGS+=(--auth "$AUTH_METHOD")
[ -n "$AUTH_ENV" ]                              && CFG_ARGS+=(--auth-env "$AUTH_ENV")
"$HERE/stages/configure.sh" "$CART_DIR" ${CFG_ARGS[@]+"${CFG_ARGS[@]}"}

# ── 4 · HARNESS (the one standard assurance gate) ──────────────────────────
say "4/4 · harness — run the standard assurance gate"
"$HERE/stages/harness.sh" "$CART_DIR" --granted "$GRANT"

say "Foundry · done — $CART_DIR"
