// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)
//
// Maps auth.method values to the canonical schema enum
// [none, api-key, oauth2, vault]. Anything that isn't already one of those
// gets normalised to "api-key" — the universal "needs a credential" label.
// The original method (when non-trivial) is preserved as a `notes_method`
// field so the credential-presentation flavour isn't lost.
//
// Conservative; lossy-by-design. A second pass can re-classify any of these
// to "oauth2" or "vault" if the cartridge in question really uses a full
// OAuth2 / Vault flow rather than a pre-issued credential.

import { walk } from "jsr:@std/fs@1/walk";

const ROOT = "/home/hyperpolymath/developer/repos/boj-server-cartridges";
const CARTS = `${ROOT}/cartridges`;

const CANONICAL = new Set(["none", "api-key", "oauth2", "vault"]);

interface Stats {
  scanned: number;
  alreadyCanonical: number;
  mapped: number;
  byOriginal: Record<string, number>;
  errors: string[];
}
const stats: Stats = { scanned: 0, alreadyCanonical: 0, mapped: 0, byOriginal: {}, errors: [] };

for await (const entry of walk(CARTS, { exts: [".json"], includeDirs: false })) {
  if (!entry.name.endsWith("cartridge.json")) continue;
  stats.scanned++;
  let text: string;
  try {
    text = await Deno.readTextFile(entry.path);
  } catch (e) {
    stats.errors.push(`${entry.path}: ${(e as Error).message}`);
    continue;
  }

  // Try line-anchored auth.method first (multiline manifests).
  const blockRe = /^([ \t]*)"method"\s*:\s*"([^"]+)"(,?)\s*(\r?\n)/m;
  const blockMatch = text.match(blockRe);
  if (blockMatch) {
    const [, indent, original, comma, newline] = blockMatch;
    if (CANONICAL.has(original)) {
      stats.alreadyCanonical++;
      continue;
    }
    stats.byOriginal[original] = (stats.byOriginal[original] ?? 0) + 1;
    // Always emit a comma between "method" and "notes_method" — only the
    // trailing comma on notes_method preserves the original presence/absence.
    text = text.replace(
      blockRe,
      `${indent}"method": "api-key",${newline}${indent}"notes_method": "${original}"${comma}${newline}`,
    );
    await Deno.writeTextFile(entry.path, text);
    stats.mapped++;
    continue;
  }

  // Fall back to inline auth: `"auth": { "method": "X", ...`
  const inlineRe = /("auth"\s*:\s*\{\s*"method"\s*:\s*)"([^"]+)"/;
  const inlineMatch = text.match(inlineRe);
  if (!inlineMatch) continue;
  const [, prefix, original] = inlineMatch;
  if (CANONICAL.has(original)) {
    stats.alreadyCanonical++;
    continue;
  }
  stats.byOriginal[original] = (stats.byOriginal[original] ?? 0) + 1;
  text = text.replace(inlineRe, `${prefix}"api-key", "notes_method": "${original}"`);
  await Deno.writeTextFile(entry.path, text);
  stats.mapped++;
}

console.log(JSON.stringify(stats, null, 2));
