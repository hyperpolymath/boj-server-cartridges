#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# The Configure stage — apply the chosen settings (endpoint, auth, tools) to a
# minted cartridge WITHOUT dropping a proof or widening the capability grant.
#
# This is the operational counterpart of `configure` in proof/Foundry.idr, where
# the stage is typed so that it preserves both indices:
#
#     configure : Artifact ds caps -> Artifact ds caps
#
# i.e. the discharged-obligation set `ds` and the capability set `caps` come out
# EXACTLY as they went in. Here that becomes two mechanically-checked rules:
#
#   PRESERVATION   the `capabilities` block written by the Provision stage is
#                  byte-identical before and after. Configure may never edit it.
#
#   NO ESCALATION  a setting whose use would REQUIRE a capability that is
#                  `locked_down` is refused. Configuration cannot smuggle in
#                  authority that provisioning denied.
#
# The capability a setting requires (universe: Net, Fs, Cred, Clock, Rand):
#
#   .api.base_url   -> `Net`, but ONLY when the URL is non-loopback. The schema
#                      defines base_url as a loopback address (`local://<name>`
#                      or `http://127.0.0.1:<port>`); a loopback backend needs no
#                      network authority, a remote one does.
#   .auth.method    -> `Cred` for anything other than `none`. Presenting a
#                      credential is exactly the authority `Cred` denotes.
#
# Usage:
#   configure.sh <cartridge-dir> [--api-base URL] [--content-type CT]
#                                [--auth METHOD] [--auth-env VAR]
#                                [--auth-source SRC]
#
#   configure.sh <dir>                      # no settings: a valid no-op
#   configure.sh <dir> --auth api-key --auth-env GITHUB_TOKEN
#
# Exit codes: 2 usage/missing cartridge · 3 missing jq · 1 escalation or invalid
# setting · 4 INTERNAL (preservation violated — should be unreachable).
set -euo pipefail

CART="${1:-}"
[ -n "$CART" ] || { echo "usage: configure.sh <cartridge-dir> [--api-base URL] [--auth METHOD] ..." >&2; exit 2; }
shift

[ -d "$CART" ] || { echo "configure: no such cartridge: $CART" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "configure: jq is required" >&2; exit 3; }
CJ="$CART/cartridge.json"
[ -f "$CJ" ] || { echo "configure: no cartridge.json at $CART" >&2; exit 2; }

API_BASE=""; CONTENT_TYPE=""; AUTH_METHOD=""; AUTH_ENV=""; AUTH_SRC=""
SET_API=0; SET_CT=0; SET_AUTH=0; SET_ENV=0; SET_SRC=0
while [ $# -gt 0 ]; do
  case "$1" in
    --api-base)     API_BASE="${2-}";    SET_API=1;  shift 2 ;;
    --content-type) CONTENT_TYPE="${2-}"; SET_CT=1;  shift 2 ;;
    --auth)         AUTH_METHOD="${2-}"; SET_AUTH=1; shift 2 ;;
    --auth-env)     AUTH_ENV="${2-}";    SET_ENV=1;  shift 2 ;;
    --auth-source)  AUTH_SRC="${2-}";    SET_SRC=1;  shift 2 ;;
    *) echo "configure: unknown arg: $1" >&2; exit 2 ;;
  esac
done

name=$(jq -r '.name // "?"' "$CJ")
echo "configure: $name"

# ── the grant we must not exceed ───────────────────────────────────────────
# Absent a capabilities block the cartridge has not been provisioned; refuse
# rather than silently configure something whose authority is unknown.
if ! jq -e '(.capabilities? | type) == "object"' "$CJ" >/dev/null 2>&1; then
  echo "configure: no capabilities block — run the Provision stage first" >&2
  exit 1
fi
CAPS_BEFORE=$(jq -cS '.capabilities' "$CJ")
granted() { jq -e --arg c "$1" '.capabilities.ephemeral | index($c) != null' "$CJ" >/dev/null 2>&1; }

deny() { # capability  setting  detail
  echo "configure: REFUSED — '$2' requires the '$1' capability, which is locked-down." >&2
  echo "           $3" >&2
  echo "           Re-provision with --granted \"...,$1\" if this authority is intended." >&2
  exit 1
}

# ── validate + capability-check each requested setting ─────────────────────
if [ "$SET_API" = 1 ]; then
  [ -n "$API_BASE" ] || { echo "configure: --api-base needs a value" >&2; exit 1; }
  # Loopback forms need no network authority; anything else does.
  case "$API_BASE" in
    local://*|http://127.0.0.1|http://127.0.0.1:*|http://localhost|http://localhost:*|http://\[::1\]|http://\[::1\]:*)
      : ;;
    *)
      granted Net || deny Net --api-base "'$API_BASE' is not a loopback address."
      ;;
  esac
fi

if [ "$SET_AUTH" = 1 ]; then
  case "$AUTH_METHOD" in
    none|api-key|oauth2|vault) : ;;
    *) echo "configure: --auth must be one of: none, api-key, oauth2, vault (got '$AUTH_METHOD')" >&2; exit 1 ;;
  esac
  if [ "$AUTH_METHOD" != none ]; then
    granted Cred || deny Cred --auth "auth method '$AUTH_METHOD' presents a credential."
  fi
fi

# `env_var` and `credential_source` exist for one purpose: to name a secret. That
# is the authority `Cred` denotes, so they require it UNCONDITIONALLY — we do not
# consult the manifest's current `auth.method` to decide.
#
# Deciding from the manifest was the earlier behaviour and it was wrong: on a
# freshly-minted cartridge `auth.method` is `none`, so credential wiring could be
# written into a cartridge whose Cred was locked-down, and a later `--auth` would
# then activate it. Requiring Cred for the act of naming a secret closes that
# two-step path and is the simpler rule to reason about.
if [ "$SET_ENV" = 1 ] || [ "$SET_SRC" = 1 ]; then
  granted Cred || deny Cred --auth-env "naming a credential source is itself credential authority."
fi

# ── apply ──────────────────────────────────────────────────────────────────
# One jq pass, so the manifest is never left half-written. `.capabilities` is
# not referenced: preservation is by construction, then verified below.
tmp=$(mktemp)
jq \
  --arg api "$API_BASE"   --argjson set_api "$SET_API" \
  --arg ct "$CONTENT_TYPE" --argjson set_ct "$SET_CT" \
  --arg am "$AUTH_METHOD" --argjson set_auth "$SET_AUTH" \
  --arg ae "$AUTH_ENV"    --argjson set_env "$SET_ENV" \
  --arg as "$AUTH_SRC"    --argjson set_src "$SET_SRC" '
  (if $set_api  == 1 then .api.base_url            = $api else . end)
  | (if $set_ct   == 1 then .api.content_type       = $ct  else . end)
  | (if $set_auth == 1 then .auth.method            = $am  else . end)
  | (if $set_env  == 1 then .auth.env_var           = (if $ae == "" then null else $ae end) else . end)
  | (if $set_src  == 1 then .auth.credential_source = (if $as == "" then null else $as end) else . end)
' "$CJ" > "$tmp" && mv "$tmp" "$CJ"

# ── PRESERVATION: the grant must be untouched ──────────────────────────────
CAPS_AFTER=$(jq -cS '.capabilities' "$CJ")
if [ "$CAPS_BEFORE" != "$CAPS_AFTER" ]; then
  echo "configure: INTERNAL — the capabilities block changed; this must never happen." >&2
  echo "  before: $CAPS_BEFORE" >&2
  echo "  after : $CAPS_AFTER"  >&2
  exit 4
fi

changed=0
report() { printf '  %-20s %s\n' "$1" "$2"; changed=1; }
[ "$SET_API"  = 1 ] && report "api.base_url"            "$(jq -r '.api.base_url'            "$CJ")"
[ "$SET_CT"   = 1 ] && report "api.content_type"        "$(jq -r '.api.content_type'        "$CJ")"
[ "$SET_AUTH" = 1 ] && report "auth.method"             "$(jq -r '.auth.method'             "$CJ")"
[ "$SET_ENV"  = 1 ] && report "auth.env_var"            "$(jq -r '.auth.env_var // "null"'  "$CJ")"
[ "$SET_SRC"  = 1 ] && report "auth.credential_source"  "$(jq -r '.auth.credential_source // "null"' "$CJ")"
[ "$changed" = 1 ] || echo "  (no settings supplied — nothing to apply)"

eph=$(jq -r '.capabilities.ephemeral | join(", ") | if . == "" then "(none)" else . end' "$CJ")
echo "  grant preserved      : [$eph]"
