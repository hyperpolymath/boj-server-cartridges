<!-- SPDX-License-Identifier: MPL-2.0 -->
<!-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath) -->

# Security Policy

## Reporting a Vulnerability

Email `j.d.a.jewell@open.ac.uk` with subject `[security] boj-server-cartridges: <summary>`.

The mailbox is the canonical estate intake; do not file public issues for unpatched vulnerabilities. Expect an acknowledgement within 72 hours and an initial assessment within 7 days. RFC 9116 (`security.txt`) advertising lives at the organisation root; the canonical security policy is mirrored from [hyperpolymath/standards](https://github.com/hyperpolymath/standards).

## Scope

`boj-server-cartridges` is a **registry** — it ships cartridge manifests (`cartridge.json`), in-tree adapter / FFI code where present, the SHA-pinned schema mirror under [`schemas/`](schemas/), and the zero-dep Deno validator under [`tools/validate-cartridges/`](tools/validate-cartridges/). The security-relevant surface is:

| Surface | What can go wrong |
|---|---|
| `auth.method` declarations in `cartridge.json` | Mis-declared auth contract leading a host to under- or over-trust a cartridge. |
| `tools/validate-cartridges/` (Deno, zero-dep) | A validator bug that silently accepts an invalid manifest in strict CI. |
| `schemas/cartridge-v1.json` + [`schemas/PINNED-SHA`](schemas/PINNED-SHA) | An out-of-sync mirror against canonical `hyperpolymath/standards`. |
| Fetcher contract documented at [`boj-server#183`](https://github.com/hyperpolymath/boj-server/issues/183) | Misuse by a downstream host that fetches manifests from this registry on demand. |
| Per-cartridge FFI / adapter source (Zig, Deno) | Standard memory- and IO-safety concerns. |

Per-cartridge runtime backends are process-isolated on loopback per [README.md](README.md); a single-cartridge compromise does not by construction reach a sibling.

## Out of scope

- Vulnerabilities in upstream tools (Deno, Zig, Idris2). Report those upstream.
- Issues in the cartridge spec itself: file against [hyperpolymath/standards](https://github.com/hyperpolymath/standards) under `cartridges/`.
- Host-side concerns (cache poisoning on a host using this registry, host-local credential handling): file against `boj-server` or the relevant host.

## Disclosure

Coordinated disclosure preferred. Public advisory after a fix is shipped to `main` and the schema-strict CI gate ([`.github/workflows/cartridge-schema.yml`](.github/workflows/cartridge-schema.yml)) is green on the patched baseline.
