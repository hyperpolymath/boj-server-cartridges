<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath) -->

# auth-method-batch-fix

One-shot tool used to close issue #19 — the canonical schema restricts
`auth.method` to `[none, api-key, oauth2, vault]`, but the migration that
seeded this repo from `boj-server/cartridges/` carried in a wider
vocabulary (`bearer_token`, `api_key`, `api_key_header`, `session-token`,
`bearer`, `basic`, `api_token`, `optional_*`).

This script walks `cartridges/`, finds the auth.method (handling both
multi-line and inline `auth: { ... }` blocks), and rewrites any
non-canonical value to `"api-key"` — the universal "needs a credential"
label. The original value is preserved verbatim under a sibling
`notes_method` field so the credential-presentation flavour
(bearer-style header vs query-param vs basic) isn't lost.

The mapping is **conservative and lossy-by-design**: a follow-up may
re-classify any of these to `"oauth2"` or `"vault"` if the cartridge in
question really uses a full flow rather than a pre-issued credential.

## Usage

```bash
cd tools/auth-method-batch-fix
deno run --allow-read --allow-write main.ts
```

The script is idempotent: any `auth.method` already in the canonical
enum is counted under `alreadyCanonical` and skipped.

After running, validate with:

```bash
cd ../validate-cartridges
deno task audit
```
