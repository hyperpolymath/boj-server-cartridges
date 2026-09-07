// SPDX-License-Identifier: MPL-2.0
import { test, expect } from "bun:test";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { validateManifest, validateTree } from "./main.js";
const valid = await Bun.file(new URL("../../cartridges/templates/gossamer-mcp/cartridge.json", import.meta.url)).json();
test("canonical template passes the actual validator", () => expect(validateManifest(valid)).toEqual([]));
for (const [label, mutate] of [
  ["required", (m) => delete m.name],
  ["nested required", (m) => delete m.auth.env_var],
  ["enum", (m) => m.tier = "Imaginary"],
  ["pattern", (m) => m.name = "../escape-mcp"],
  ["minItems", (m) => m.protocols = []],
  ["type", (m) => m.auth = 1],
  ["minimum", (m) => m.ports = {allowed: [0], denied: []}],
  ["maximum", (m) => m.ports = {allowed: [65536], denied: []}],
  ["integer", (m) => m.ports = {allowed: [3.5], denied: []}],
  ["uri", (m) => m.$schema = "not a URI"]
]) test(`rejects ${label}`, () => {
  const manifest = structuredClone(valid); mutate(manifest);
  expect(validateManifest(manifest).length).toBeGreaterThan(0);
});
test("empty tree and malformed JSON fail; a planted valid manifest passes", async () => {
  const root = await mkdtemp(join(tmpdir(), "boj-validator-"));
  try {
    await expect(validateTree(root)).rejects.toThrow("No cartridge manifests");
    await writeFile(join(root, "cartridge.json"), JSON.stringify(valid));
    expect((await validateTree(root))[0].errors).toEqual([]);
    await writeFile(join(root, "cartridge.json"), "{");
    expect((await validateTree(root))[0].errors.length).toBeGreaterThan(0);
  } finally { await rm(root, {recursive: true}); }
});
