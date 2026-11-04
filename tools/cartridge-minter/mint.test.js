// SPDX-License-Identifier: MPL-2.0
import { test, expect } from "bun:test";
import { mkdtemp, rm, writeFile, readFile, readdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { mint, validate, destinationFor } from "./mint.js";
import { validateManifest } from "../validate-cartridges/main.js";
const templateDir = fileURLToPath(new URL("../../cartridges/templates/gossamer-mcp/", import.meta.url));

/** Snapshot every copied directory and byte payload, excluding generated root files. */
async function scaffoldContents(root, relative = "") {
  const entries = await readdir(join(root, relative), {withFileTypes: true});
  entries.sort((left, right) => left.name.localeCompare(right.name));
  const result = [];
  for (const entry of entries) {
    const path = join(relative, entry.name);
    if (!relative && (entry.name === "cartridge.json" || entry.name === "minter.toml")) continue;
    if (entry.isDirectory()) {
      result.push([path, "directory"]);
      result.push(...await scaffoldContents(root, path));
    } else if (entry.isFile()) {
      result.push([path, "file", (await readFile(join(root, path))).toString("hex")]);
    } else {
      throw new Error(`unsupported scaffold entry: ${path}`);
    }
  }
  return result;
}

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
    expect(await readFile(join(dest, "mod.js"), "utf8")).toBe(await readFile(new URL("../../cartridges/templates/gossamer-mcp/mod.js", import.meta.url), "utf8"));
    expect(await scaffoldContents(dest)).toEqual(await scaffoldContents(templateDir));
    await expect(mint(config, dest)).rejects.toThrow("already exists");
    expect(JSON.parse(await readFile(join(dest, "cartridge.json"), "utf8"))).toEqual(manifest);
  } finally { await rm(root, {recursive:true}); }
});

test("concurrent minters reserve one complete destination and reject the other writer", async () => {
  const root = await mkdtemp(join(tmpdir(), "boj-mint-race-"));
  try {
    const config = join(root, "minter.toml"), dest = join(root, "result");
    await writeFile(config, Object.entries(cfg).map(([key,value]) => `${key} = ${JSON.stringify(value)}`).join("\n"));
    const results = await Promise.allSettled([mint(config, dest), mint(config, dest)]);
    expect(results.filter((result) => result.status === "fulfilled")).toHaveLength(1);
    const failures = results.filter((result) => result.status === "rejected");
    expect(failures).toHaveLength(1);
    expect(failures[0].reason.code === "EEXIST" || /already exists/.test(failures[0].reason.message)).toBe(true);
    const manifest = JSON.parse(await readFile(join(dest, "cartridge.json"), "utf8"));
    expect(validateManifest(manifest)).toEqual([]);
    expect(manifest.name).toBe(cfg.name);
    expect(manifest.available).toBe(false);
    expect(await readFile(join(dest, "minter.toml"), "utf8")).toBe(await readFile(config, "utf8"));
    expect(await readFile(join(dest, "mod.js"), "utf8")).toBe(await readFile(new URL("../../cartridges/templates/gossamer-mcp/mod.js", import.meta.url), "utf8"));
    expect(await scaffoldContents(dest)).toEqual(await scaffoldContents(templateDir));
  } finally { await rm(root, {recursive:true}); }
});
