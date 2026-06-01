// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)
//
// Backfills missing top-level + nested required fields on cartridge
// manifests to close issue #20:
//   - protocols (inferred from name suffix: -mcp → ["MCP"], -lsp → ["LSP"], …)
//   - api ({ "base_url": "local://<name>", "content_type": "application/json" })
//   - auth.env_var / auth.credential_source (set to null)
//   - tools[i].inputSchema (set to { "type": "object", "properties": {} })
//
// Skips the three name-pattern stragglers (boj-health, origenemcp,
// opendatamcp) — those are renames that need owner decision.

import { walk } from "jsr:@std/fs@1/walk";

const ROOT = "/home/hyperpolymath/developer/repos/boj-server-cartridges";
const CARTS = `${ROOT}/cartridges`;
const SCHEMA_PATH = `${ROOT}/schemas/cartridge-v1.json`;

const ROLE_TO_PROTO: Record<string, string> = {
  mcp: "MCP",
  lsp: "LSP",
  dap: "DAP",
  bsp: "BSP",
  debug: "Debug",
  format: "Format",
  lint: "Lint",
  build: "Build",
  nesy: "NeSy",
  agentic: "Agentic",
  fleet: "Fleet",
};

// Historical: the renames in PR closing #20 (boj-health→boj-health-mcp,
// origenemcp→origene-mcp, opendatamcp→opendata-mcp) cleared the
// name-pattern stragglers. Set is intentionally empty now.
const SKIP_NAMES = new Set<string>([]);

type Manifest = Record<string, unknown>;

interface Stats {
  scanned: number;
  alreadyComplete: number;
  patched: number;
  skippedNameRename: number;
  perFix: Record<string, number>;
  errors: string[];
}
const stats: Stats = {
  scanned: 0,
  alreadyComplete: 0,
  patched: 0,
  skippedNameRename: 0,
  perFix: {},
  errors: [],
};

function deriveProtocols(name: string): string[] | null {
  const m = name.match(/-(\w+)$/);
  if (!m) return null;
  const proto = ROLE_TO_PROTO[m[1]];
  if (!proto) return null;
  return [proto];
}

// Re-serialise with 2-space indent + a property ordering close to the
// schema's `required` list. Properties not in the schema's order are
// appended in encounter order.
const SCHEMA_ORDER = [
  "$schema",
  "spdx",
  "copyright",
  "name",
  "version",
  "status",
  "description",
  "domain",
  "category",
  "tier",
  "protocols",
  "auth",
  "api",
  "ports",
  "tools",
  "states",
  "source",
];

function orderObject(obj: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const k of SCHEMA_ORDER) if (k in obj) out[k] = obj[k];
  for (const k of Object.keys(obj)) if (!(k in out)) out[k] = obj[k];
  return out;
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
  let m: Manifest;
  try {
    m = JSON.parse(text) as Manifest;
  } catch (e) {
    stats.errors.push(`${entry.path}: parse - ${(e as Error).message}`);
    continue;
  }
  const name = typeof m.name === "string" ? m.name : "";
  if (SKIP_NAMES.has(name)) {
    stats.skippedNameRename++;
    continue;
  }

  let patched = false;

  // 1) protocols
  if (!("protocols" in m)) {
    const p = deriveProtocols(name);
    if (p) {
      m.protocols = p;
      stats.perFix.protocols = (stats.perFix.protocols ?? 0) + 1;
      patched = true;
    }
  }

  // 2) api
  if (!("api" in m)) {
    m.api = { base_url: `local://${name}`, content_type: "application/json" };
    stats.perFix.api = (stats.perFix.api ?? 0) + 1;
    patched = true;
  }

  // 3) auth.env_var / auth.credential_source
  if (m.auth && typeof m.auth === "object" && !Array.isArray(m.auth)) {
    const auth = m.auth as Record<string, unknown>;
    if (!("env_var" in auth)) {
      auth.env_var = null;
      stats.perFix["auth.env_var"] = (stats.perFix["auth.env_var"] ?? 0) + 1;
      patched = true;
    }
    if (!("credential_source" in auth)) {
      auth.credential_source = null;
      stats.perFix["auth.credential_source"] = (stats.perFix["auth.credential_source"] ?? 0) + 1;
      patched = true;
    }
  }

  // 4) tools[i].inputSchema
  if (Array.isArray(m.tools)) {
    for (const tool of m.tools as Array<Record<string, unknown>>) {
      if (typeof tool === "object" && tool !== null && !("inputSchema" in tool)) {
        tool.inputSchema = { type: "object", properties: {} };
        stats.perFix["tools[*].inputSchema"] = (stats.perFix["tools[*].inputSchema"] ?? 0) + 1;
        patched = true;
      }
    }
  }

  if (!patched) {
    stats.alreadyComplete++;
    continue;
  }

  const ordered = orderObject(m);
  const newText = JSON.stringify(ordered, null, 2) + "\n";
  await Deno.writeTextFile(entry.path, newText);
  stats.patched++;
}

console.log(JSON.stringify(stats, null, 2));
