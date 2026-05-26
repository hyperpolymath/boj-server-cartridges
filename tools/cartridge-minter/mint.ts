#!/usr/bin/env -S deno run --allow-read --allow-write
// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)
//
// Cartridge minter — scaffolds a new BoJ cartridge from a minter.toml config.
//
// Usage:
//   deno run --allow-read --allow-write tools/cartridge-minter/mint.ts <minter.toml> [--dest <path>]
//
// If --dest is omitted, the cartridge is placed at the canonical location
// derived from minter.toml's `domain` + `name`:
//   - `category = "domain"` (default):    cartridges/domains/<domain>/<name>/
//   - `category = "cross-cutting"`:       cartridges/cross-cutting/<subcategory>/<name>/
//   - `category = "template"`:            cartridges/templates/<name>/
//
// The minter reads the canonical template at cartridges/templates/gossamer-mcp/,
// copies it to <dest>, then performs string substitutions in cartridge.json,
// mod.js, README.adoc.

import { parse as parseToml } from "https://deno.land/std@0.224.0/toml/mod.ts";
import { ensureDir, copy } from "https://deno.land/std@0.224.0/fs/mod.ts";
import { join, dirname, fromFileUrl } from "https://deno.land/std@0.224.0/path/mod.ts";

const REPO_ROOT = dirname(dirname(dirname(fromFileUrl(import.meta.url))));
const TEMPLATE_DIR = join(REPO_ROOT, "cartridges", "templates", "gossamer-mcp");
const ROLE_RE = /-(mcp|lsp|dap|bsp|debug|format|lint|build|nesy|agentic|fleet)$/;
const DOMAIN_NORMALISE: Record<string, string> = {
  "Cloud": "cloud", "Database": "database", "Registry": "registry",
  "Productivity": "productivity", "Languages": "languages", "Security": "security",
  "Research": "research", "Monitoring": "observability", "Container": "container",
  "Container Orchestration": "container", "Package Management": "registry",
  "CI/CD": "ci-cd", "Communications": "communications", "Comms": "communications",
  "AI": "ai", "Browser": "automation", "Knowledge": "knowledge",
  "Secrets": "security", "Git": "development", "Embedded": "languages",
  "Code Quality": "code-quality",
};

interface MinterConfig {
  name: string;
  description: string;
  version: string;
  domain: string;
  protocols: string[];
  tier: "Teranga" | "Shield" | "Ayo";
  category?: "domain" | "cross-cutting" | "template";
  cross_cutting_category?: string;
  backend?: string;
  generate_panel?: boolean;
  auth?: Record<string, unknown> | string;
  api?: Record<string, unknown>;
  api_base?: string;
  services?: Record<string, string>;
}

function normaliseDomain(raw: string): string {
  return DOMAIN_NORMALISE[raw]
    ?? raw.toLowerCase().replaceAll(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
}

function validate(cfg: MinterConfig): void {
  const errors: string[] = [];
  if (!cfg.name) errors.push("missing name");
  else if (!ROLE_RE.test(cfg.name)) {
    errors.push(`name '${cfg.name}' must end in a canonical role suffix (-mcp|-lsp|-dap|-bsp|-debug|-format|-lint|-build|-nesy|-agentic|-fleet)`);
  }
  if (!cfg.description) errors.push("missing description");
  if (!cfg.version) errors.push("missing version");
  else if (!/^\d+\.\d+\.\d+(-[a-z0-9.-]+)?$/.test(cfg.version)) {
    errors.push(`version '${cfg.version}' must be semver`);
  }
  if (!cfg.domain) errors.push("missing domain");
  if (!cfg.protocols || cfg.protocols.length === 0) errors.push("missing protocols");
  if (!cfg.tier) errors.push("missing tier");
  else if (!["Teranga", "Shield", "Ayo"].includes(cfg.tier)) {
    errors.push(`tier '${cfg.tier}' must be one of Teranga | Shield | Ayo`);
  }
  if (errors.length > 0) {
    throw new Error("minter.toml validation failed:\n  - " + errors.join("\n  - "));
  }
}

function destinationFor(cfg: MinterConfig): string {
  const cat = cfg.category ?? "domain";
  if (cat === "template") {
    return join(REPO_ROOT, "cartridges", "templates", cfg.name);
  }
  if (cat === "cross-cutting") {
    const sub = cfg.cross_cutting_category ?? "agentic";
    return join(REPO_ROOT, "cartridges", "cross-cutting", sub, cfg.name);
  }
  return join(REPO_ROOT, "cartridges", "domains", normaliseDomain(cfg.domain), cfg.name);
}

function buildCartridgeJson(cfg: MinterConfig): Record<string, unknown> {
  const role = cfg.name.match(ROLE_RE)![1];
  // Normalise auth shape: accept either string (e.g. "bearer") or object form.
  let auth: Record<string, unknown>;
  if (typeof cfg.auth === "string") {
    auth = { method: cfg.auth, env_var: null, credential_source: null };
  } else {
    auth = {
      method: cfg.auth?.method ?? "none",
      env_var: cfg.auth?.env_var ?? null,
      credential_source: cfg.auth?.credential_source ?? null,
    };
  }
  const api = cfg.api ?? {
    base_url: cfg.api_base ?? `local://${cfg.name}`,
    content_type: "application/json",
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
    tools: [],
  };
}

async function mint(configPath: string, explicitDest?: string): Promise<void> {
  const tomlText = await Deno.readTextFile(configPath);
  const cfg = parseToml(tomlText) as unknown as MinterConfig;
  validate(cfg);
  const dest = explicitDest ?? destinationFor(cfg);

  // Refuse to overwrite
  try {
    await Deno.stat(dest);
    throw new Error(`destination already exists: ${dest}`);
  } catch (e) {
    if (!(e instanceof Deno.errors.NotFound)) throw e;
  }

  // Copy template tree, then overwrite manifest with the computed one.
  await copy(TEMPLATE_DIR, dest);
  const manifest = buildCartridgeJson(cfg);
  await Deno.writeTextFile(
    join(dest, "cartridge.json"),
    JSON.stringify(manifest, null, 2) + "\n",
  );
  // Also drop the minter.toml inside the new cartridge so re-mints / regeneration are reproducible.
  await Deno.writeTextFile(join(dest, "minter.toml"), tomlText);

  console.log(`✓ Minted ${cfg.name} → ${dest}`);
  console.log(`  Edit cartridge.json to declare your tools array.`);
  console.log(`  Edit mod.js / adapter/ / ffi/ / abi/ as your implementation requires.`);
}

if (import.meta.main) {
  const args = Deno.args;
  if (args.length === 0 || args[0] === "--help" || args[0] === "-h") {
    console.log("Usage: mint.ts <minter.toml> [--dest <path>]");
    console.log("");
    console.log("Scaffolds a new BoJ cartridge by copying templates/gossamer-mcp/");
    console.log("and customising the manifest based on the minter.toml config.");
    Deno.exit(args.length === 0 ? 1 : 0);
  }
  const configPath = args[0];
  let dest: string | undefined;
  const destIdx = args.indexOf("--dest");
  if (destIdx >= 0 && destIdx < args.length - 1) {
    dest = args[destIdx + 1];
  }
  await mint(configPath, dest);
}
