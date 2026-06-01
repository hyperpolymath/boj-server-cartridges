// SPDX-License-Identifier: MPL-2.0
// Walks cartridges/, derives category from path, inserts "category": "<value>"
// into each cartridge.json that lacks it. Preserves existing formatting by
// doing a string-level insertion after the `"domain"` line.

import { walk } from "jsr:@std/fs@1/walk";

const ROOT = "/home/hyperpolymath/developer/repos/boj-server-cartridges";
const CARTS = `${ROOT}/cartridges`;

interface Stats {
  scanned: number;
  alreadyHad: number;
  added: number;
  skippedNoDomain: number;
  errors: string[];
}
const stats: Stats = { scanned: 0, alreadyHad: 0, added: 0, skippedNoDomain: 0, errors: [] };

function deriveCategory(path: string): string | null {
  const rel = path.replace(CARTS + "/", "");
  if (rel.startsWith("domains/")) return "domain";
  if (rel.startsWith("cross-cutting/")) return "cross-cutting";
  if (rel.startsWith("templates/")) return "template";
  return null;
}

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
  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(text);
  } catch (e) {
    stats.errors.push(`${entry.path}: parse - ${(e as Error).message}`);
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

  // String-level insertion: find the "domain" line, insert "category" right after it.
  // Pattern matches: <indent>"domain": "<value>"<,?><newline>
  const domainLine = /^([ \t]*)"domain"\s*:\s*"[^"]*",?\s*(\r?\n)/m;
  const match = text.match(domainLine);
  if (!match) {
    // Fallback: try inserting before "tier" (since gossamer/schema put category right after domain).
    const tierLine = /^([ \t]*)"tier"\s*:/m;
    const tierMatch = text.match(tierLine);
    if (!tierMatch) {
      stats.skippedNoDomain++;
      stats.errors.push(`${entry.path}: no "domain" or "tier" line found to anchor insertion`);
      continue;
    }
    const indent = tierMatch[1];
    const insertAt = text.indexOf(tierMatch[0]);
    text = text.slice(0, insertAt) +
      `${indent}"category": "${category}",\n` +
      text.slice(insertAt);
  } else {
    const indent = match[1];
    const newline = match[2];
    const insertAfter = (match.index ?? 0) + match[0].length;
    text = text.slice(0, insertAfter) +
      `${indent}"category": "${category}",${newline}` +
      text.slice(insertAfter);
  }

  await Deno.writeTextFile(entry.path, text);
  stats.added++;
}

console.log(JSON.stringify(stats, null, 2));
