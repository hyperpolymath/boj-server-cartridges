// SPDX-License-Identifier: MPL-2.0
import { readdir, readFile, writeFile, cp, mkdir } from "node:fs/promises";
import { join } from "node:path";
export const readTextFile = (path) => readFile(path, "utf8");
export const writeTextFile = (path, data) => writeFile(path, data, "utf8");
export const ensureDir = (path) => mkdir(path, { recursive: true });
export const copy = (source, dest) => cp(source, dest, { recursive: true, errorOnExist: true, force: false });
// Deterministic traversal; symlinks are never followed into another repository.
export async function* walk(root, options = {}) {
  const entries = (await readdir(root, { withFileTypes: true })).sort((a, b) => a.name.localeCompare(b.name));
  for (const entry of entries) {
    const path = join(root, entry.name);
    if (entry.isSymbolicLink()) continue;
    if (entry.isDirectory()) {
      if (options.includeDirs !== false) yield { path, name: entry.name, isDirectory: true, isFile: false };
      yield* walk(path, options);
    } else if (entry.isFile() && (!options.match || options.match.some((re) => re.test(path)))) {
      yield { path, name: entry.name, isDirectory: false, isFile: true };
    }
  }
}
