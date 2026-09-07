import { validateManifest } from "../validate-cartridges/main.js";
// SPDX-License-Identifier: MPL-2.0
import { readTextFile, writeTextFile } from "../lib/files.js";
import { stat, mkdir } from "node:fs/promises";
const parseToml = Bun.TOML.parse;
import { ensureDir, copy } from "../lib/files.js";
import { join, dirname } from "node:path";
import { fileURLToPath as fromFileUrl } from "node:url";
const REPO_ROOT = dirname(dirname(dirname(fromFileUrl(import.meta.url)))), TEMPLATE_DIR = join(REPO_ROOT, "cartridges", "templates", "gossamer-mcp"), ROLE_RE = /-(mcp|lsp|dap|bsp|debug|format|lint|build|nesy|agentic|fleet)$/, DOMAIN_NORMALISE = {
  Cloud: "cloud",
  Database: "database",
  Registry: "registry",
  Productivity: "productivity",
  Languages: "languages",
  Security: "security",
  Research: "research",
  Monitoring: "observability",
  Container: "container",
  "Container Orchestration": "container",
  "Package Management": "registry",
  "CI/CD": "ci-cd",
  Communications: "communications",
  Comms: "communications",
  AI: "ai",
  Browser: "automation",
  Knowledge: "knowledge",
  Secrets: "security",
  Git: "development",
  Embedded: "languages",
  "Code Quality": "code-quality"
};
function normaliseDomain(raw) {
  return DOMAIN_NORMALISE[raw] ?? raw.toLowerCase().replaceAll(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
}
export function validate(cfg) {
  const errors = [];
  if (typeof cfg.name !== "string" || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(cfg.name))
    errors.push("missing name");
  else if (!ROLE_RE.test(cfg.name))
    errors.push(`name '${cfg.name}' must end in a canonical role suffix (-mcp|-lsp|-dap|-bsp|-debug|-format|-lint|-build|-nesy|-agentic|-fleet)`);
  if (!cfg.description)
    errors.push("missing description");
  if (!cfg.version)
    errors.push("missing version");
  else if (!/^\d+\.\d+\.\d+(-[a-z0-9.-]+)?$/.test(cfg.version))
    errors.push(`version '${cfg.version}' must be semver`);
  if (!cfg.domain)
    errors.push("missing domain");
  if (!cfg.protocols || cfg.protocols.length === 0)
    errors.push("missing protocols");
  if (!cfg.tier)
    errors.push("missing tier");
  else if (!["Teranga", "Shield", "Ayo"].includes(cfg.tier))
    errors.push(`tier '${cfg.tier}' must be one of Teranga | Shield | Ayo`);
  if (cfg.cross_cutting_category && !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(cfg.cross_cutting_category))
    errors.push("invalid cross_cutting_category");
  if (cfg.category && !["domain", "cross-cutting", "template"].includes(cfg.category))
    errors.push("invalid category");
  if (errors.length > 0)
    throw Error(`minter.toml validation failed:
  - ` + errors.join(`
  - `));
}
export function destinationFor(cfg) {
  const cat = cfg.category ?? "domain";
  if (cat === "template")
    return join(REPO_ROOT, "cartridges", "templates", cfg.name);
  if (cat === "cross-cutting") {
    const sub = cfg.cross_cutting_category ?? "agentic";
    return join(REPO_ROOT, "cartridges", "cross-cutting", sub, cfg.name);
  }
  return join(REPO_ROOT, "cartridges", "domains", normaliseDomain(cfg.domain), cfg.name);
}
export function buildCartridgeJson(cfg) {
  const role = cfg.name.match(ROLE_RE)[1];
  let auth;
  if (typeof cfg.auth === "string")
    auth = { method: cfg.auth, env_var: null, credential_source: null };
  else
    auth = {
      method: cfg.auth?.method ?? "none",
      env_var: cfg.auth?.env_var ?? null,
      credential_source: cfg.auth?.credential_source ?? null
    };
  const api = cfg.api ?? {
    base_url: cfg.api_base ?? `local://${cfg.name}`,
    content_type: "application/json"
  };
  return {
    $schema: "https://hyperpolymath.dev/standards/cartridges/cartridge-v1.json",
    spdx: "MPL-2.0",
    copyright: "Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)",
    name: cfg.name,
    version: cfg.version,
    description: cfg.description,
    domain: normaliseDomain(cfg.domain),
    category: cfg.category ?? "domain",
    tier: cfg.tier,
    protocols: cfg.protocols,
    auth,
    api,
    available: false,
    status: "scaffold",
    tools: []
  };
}
export async function mint(configPath, explicitDest) {
  const tomlText = await readTextFile(configPath), cfg = parseToml(tomlText);
  validate(cfg);
  const dest = explicitDest ?? destinationFor(cfg);
  try {
    await stat(dest);
    throw Error(`destination already exists: ${dest}`);
  } catch (e) {
    if (e.code !== "ENOENT")
      throw e;
  }
  const manifest = buildCartridgeJson(cfg);
  const issues = validateManifest(manifest);
  if (issues.length) throw new Error(`Invalid generated manifest: ${JSON.stringify(issues)}`);
  // Reserve the destination atomically. A racing minter must fail here.
  await mkdir(dirname(dest), {recursive: true});
  await mkdir(dest, {recursive: false});
  await copy(TEMPLATE_DIR, dest);
  await writeTextFile(join(dest, "cartridge.json"), JSON.stringify(manifest, null, 2) + `
`);
  await writeTextFile(join(dest, "minter.toml"), tomlText);
  if (process.argv.includes("--print-destination")) {
    console.log(dest);
    return;
  }
  console.log(`\u2713 Minted ${cfg.name} \u2192 ${dest}`);
  console.log("  Edit cartridge.json to declare your tools array.");
  console.log("  Edit mod.js / adapter/ / ffi/ / abi/ as your implementation requires.");
}
if (import.meta.main) {
  const args = process.argv.slice(2);
  if (args.length === 0 || args[0] === "--help" || args[0] === "-h") {
    console.log("Usage: mint.js <minter.toml> [--dest <path>]");
    console.log("");
    console.log("Scaffolds a new BoJ cartridge by copying templates/gossamer-mcp/");
    console.log("and customising the manifest based on the minter.toml config.");
    process.exit(args.length === 0 ? 1 : 0);
  }
  const configPath = args[0];
  let dest;
  const destIdx = args.indexOf("--dest");
  if (destIdx >= 0 && destIdx < args.length - 1)
    dest = args[destIdx + 1];
  await mint(configPath, dest);
}
