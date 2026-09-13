// SPDX-License-Identifier: MPL-2.0
import { readdir, readFile, writeFile, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
export const readTextFile = (path) => readFile(path, "utf8");
export const writeTextFile = (path, data) => writeFile(path, data, "utf8");
export const makeTempDir = () => mkdtemp(join(tmpdir(), "boj-lsp-"));
export const remove = rm;
export async function* readDir(path) {
  for (const entry of await readdir(path, {withFileTypes: true})) {
    yield {name: entry.name, isFile: entry.isFile(), isDirectory: entry.isDirectory()};
  }
}
