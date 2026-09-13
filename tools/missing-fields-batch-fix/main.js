// SPDX-License-Identifier: MPL-2.0
import { readTextFile, writeTextFile } from "../lib/files.js";
import { stat } from "node:fs/promises";
import { walk } from "../lib/files.js";
const ROOT = "/home/hyperpolymath/developer/repos/boj-server-cartridges", CARTS = `${ROOT}/cartridges`, SCHEMA_PATH = `${ROOT}/schemas/cartridge-v1.json`, ROLE_TO_PROTO = {
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
  fleet: "Fleet"
}, SKIP_NAMES = new Set([]), stats = {
  scanned: 0,
  alreadyComplete: 0,
  patched: 0,
  skippedNameRename: 0,
  perFix: {},
  errors: []
};
function deriveProtocols(name) {
  const m = name.match(/-(\w+)$/);
  if (!m)
    return null;
  const proto = ROLE_TO_PROTO[m[1]];
  if (!proto)
    return null;
  return [proto];
}
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
  "source"
];
function orderObject(obj) {
  const out = {};
  for (const k of SCHEMA_ORDER)
    if (k in obj)
      out[k] = obj[k];
  for (const k of Object.keys(obj))
    if (!(k in out))
      out[k] = obj[k];
  return out;
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
  let m;
  try {
    m = JSON.parse(text);
  } catch (e) {
    stats.errors.push(`${entry.path}: parse - ${e.message}`);
    continue;
  }
  const name = typeof m.name === "string" ? m.name : "";
  if (SKIP_NAMES.has(name)) {
    stats.skippedNameRename++;
    continue;
  }
  let patched = !1;
  if (!("protocols" in m)) {
    const p = deriveProtocols(name);
    if (p) {
      m.protocols = p;
      stats.perFix.protocols = (stats.perFix.protocols ?? 0) + 1;
      patched = !0;
    }
  }
  if (!("api" in m)) {
    m.api = { base_url: `local://${name}`, content_type: "application/json" };
    stats.perFix.api = (stats.perFix.api ?? 0) + 1;
    patched = !0;
  }
  if (m.auth && typeof m.auth === "object" && !Array.isArray(m.auth)) {
    const auth = m.auth;
    if (!("env_var" in auth)) {
      auth.env_var = null;
      stats.perFix["auth.env_var"] = (stats.perFix["auth.env_var"] ?? 0) + 1;
      patched = !0;
    }
    if (!("credential_source" in auth)) {
      auth.credential_source = null;
      stats.perFix["auth.credential_source"] = (stats.perFix["auth.credential_source"] ?? 0) + 1;
      patched = !0;
    }
  }
  if (Array.isArray(m.tools)) {
    for (const tool of m.tools)
      if (typeof tool === "object" && tool !== null && !("inputSchema" in tool)) {
        tool.inputSchema = { type: "object", properties: {} };
        stats.perFix["tools[*].inputSchema"] = (stats.perFix["tools[*].inputSchema"] ?? 0) + 1;
        patched = !0;
      }
  }
  if (!patched) {
    stats.alreadyComplete++;
    continue;
  }
  const ordered = orderObject(m), newText = JSON.stringify(ordered, null, 2) + `
`;
  await writeTextFile(entry.path, newText);
  stats.patched++;
}
console.log(JSON.stringify(stats, null, 2));
