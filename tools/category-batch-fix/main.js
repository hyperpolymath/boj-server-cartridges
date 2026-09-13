// SPDX-License-Identifier: MPL-2.0
import { readTextFile, writeTextFile } from "../lib/files.js";
import { stat } from "node:fs/promises";
import { walk } from "../lib/files.js";
const ROOT = "/home/hyperpolymath/developer/repos/boj-server-cartridges", CARTS = `${ROOT}/cartridges`, stats = { scanned: 0, alreadyHad: 0, added: 0, skippedNoDomain: 0, errors: [] };
function deriveCategory(path) {
  const rel = path.replace(CARTS + "/", "");
  if (rel.startsWith("domains/"))
    return "domain";
  if (rel.startsWith("cross-cutting/"))
    return "cross-cutting";
  if (rel.startsWith("templates/"))
    return "template";
  return null;
}
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
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch (e) {
    stats.errors.push(`${entry.path}: parse - ${e.message}`);
    continue;
  }
  if (Object.prototype.hasOwnProperty.call(parsed, "category")) {
    stats.alreadyHad++;
    continue;
  }
  const category = deriveCategory(entry.path);
  if (!category) {
    stats.errors.push(`${entry.path}: could not derive category from path`);
    continue;
  }
  const domainLine = /^([ \t]*)"domain"\s*:\s*"[^"]*",?\s*(\r?\n)/m, match = text.match(domainLine);
  if (!match) {
    const tierLine = /^([ \t]*)"tier"\s*:/m, tierMatch = text.match(tierLine);
    if (!tierMatch) {
      stats.skippedNoDomain++;
      stats.errors.push(`${entry.path}: no "domain" or "tier" line found to anchor insertion`);
      continue;
    }
    const indent = tierMatch[1], insertAt = text.indexOf(tierMatch[0]);
    text = text.slice(0, insertAt) + `${indent}"category": "${category}",
` + text.slice(insertAt);
  } else {
    const indent = match[1], newline = match[2], insertAfter = (match.index ?? 0) + match[0].length;
    text = text.slice(0, insertAfter) + `${indent}"category": "${category}",${newline}` + text.slice(insertAfter);
  }
  await writeTextFile(entry.path, text);
  stats.added++;
}
console.log(JSON.stringify(stats, null, 2));
