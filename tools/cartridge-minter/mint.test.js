// SPDX-License-Identifier: MPL-2.0
import { test, expect } from "bun:test";
import { mkdtemp, rm, writeFile, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { mint, validate, destinationFor } from "./mint.js";
import { validateManifest } from "../validate-cartridges/main.js";
const cfg = {name: "example-mcp", description: "Test", version: "0.1.0", domain: "CI/CD", protocols: ["MCP"], tier: "Ayo"};
test("minter rejects path traversal and unknown categories before writing", () => {
  expect(() => validate({...cfg, name: "../example-mcp"})).toThrow();
  expect(() => validate({...cfg, cross_cutting_category: "../escape"})).toThrow();
  expect(() => validate({...cfg, category: "typo"})).toThrow();
  expect(destinationFor(cfg)).toEndWith("cartridges/domains/ci-cd/example-mcp");
});
test("mint creates a valid unavailable scaffold and refuses to overwrite", async () => {
  const root = await mkdtemp(join(tmpdir(), "boj-mint-"));
  try {
    const config = join(root, "minter.toml"), dest = join(root, "result");
    await writeFile(config, Object.entries(cfg).map(([key,value]) => `${key} = ${JSON.stringify(value)}`).join("\n"));
    await mint(config, dest);
    const manifest = JSON.parse(await readFile(join(dest, "cartridge.json"), "utf8"));
    expect(validateManifest(manifest)).toEqual([]);
    expect(manifest.available).toBe(false);
    expect(manifest.tools).toEqual([]);
    await expect(mint(config, dest)).rejects.toThrow("already exists");
    expect(JSON.parse(await readFile(join(dest, "cartridge.json"), "utf8"))).toEqual(manifest);
  } finally { await rm(root, {recursive:true}); }
});
