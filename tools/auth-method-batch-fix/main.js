// SPDX-License-Identifier: MPL-2.0
import { readTextFile, writeTextFile } from "../lib/files.js";
import { stat } from "node:fs/promises";
import { walk } from "../lib/files.js";
const ROOT = "/home/hyperpolymath/developer/repos/boj-server-cartridges", CARTS = `${ROOT}/cartridges`, CANONICAL = new Set(["none", "api-key", "oauth2", "vault"]), stats = { scanned: 0, alreadyCanonical: 0, mapped: 0, byOriginal: {}, errors: [] };
for await (const entry of walk(CARTS, { exts: [".json"], includeDirs: !1 })) {
  if (!entry.name.endsWith("cartridge.json"))
    continue;
  stats.scanned++;
  let text;
  try {
    text = await readTextFile(entry.path);
  } catch (e) {
    stats.errors.push(`${entry.path}: ${e.message}`);
    continue;
  }
  const blockRe = /^([ \t]*)"method"\s*:\s*"([^"]+)"(,?)\s*(\r?\n)/m, blockMatch = text.match(blockRe);
  if (blockMatch) {
    const [, indent, original, comma, newline] = blockMatch;
    if (CANONICAL.has(original)) {
      stats.alreadyCanonical++;
      continue;
    }
    stats.byOriginal[original] = (stats.byOriginal[original] ?? 0) + 1;
    text = text.replace(blockRe, `${indent}"method": "api-key",${newline}${indent}"notes_method": "${original}"${comma}${newline}`);
    await writeTextFile(entry.path, text);
    stats.mapped++;
    continue;
  }
  const inlineRe = /("auth"\s*:\s*\{\s*"method"\s*:\s*)"([^"]+)"/, inlineMatch = text.match(inlineRe);
  if (!inlineMatch)
    continue;
  const [, prefix, original] = inlineMatch;
  if (CANONICAL.has(original)) {
    stats.alreadyCanonical++;
    continue;
  }
  stats.byOriginal[original] = (stats.byOriginal[original] ?? 0) + 1;
  text = text.replace(inlineRe, `${prefix}"api-key", "notes_method": "${original}"`);
  await writeTextFile(entry.path, text);
  stats.mapped++;
}
console.log(JSON.stringify(stats, null, 2));
