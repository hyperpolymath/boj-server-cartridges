// SPDX-License-Identifier: MPL-2.0
import { readTextFile, writeTextFile } from "../lib/files.js";
import { stat } from "node:fs/promises";
import { walk } from "../lib/files.js";
import { join, relative } from "node:path";
import { fileURLToPath as fromFileUrl } from "node:url";
const ROOT = fromFileUrl(new URL("../..", import.meta.url)), CARTRIDGES_DIR = join(ROOT, "cartridges"), CATALOG_PATH = join(ROOT, "site", "catalog.json"), INDEX_PATH = join(ROOT, "site", "index.html"), REGISTRY = "https://github.com/hyperpolymath/boj-server-cartridges", TEMPLATE_GROUP = "templates";
function str(v, fallback = "") {
  return typeof v === "string" ? v : fallback;
}
async function collect() {
  const entries = [], skipped = [];
  for await (const found of walk(CARTRIDGES_DIR, {
    includeDirs: !1,
    match: [/cartridge\.json$/]
  })) {
    const dir = found.path.slice(0, -15), rel = relative(ROOT, dir).replaceAll("\\", "/"), segs = relative(CARTRIDGES_DIR, dir).replaceAll("\\", "/").split("/"), group = segs[0] ?? "";
    if (group === TEMPLATE_GROUP) {
      skipped.push(rel);
      continue;
    }
    let m;
    try {
      m = JSON.parse(await readTextFile(found.path));
    } catch (e) {
      throw Error(`${rel}/cartridge.json: unparseable \u2014 ${e.message}`);
    }
    const auth = m.auth, tools = Array.isArray(m.tools) ? m.tools : [], protocols = Array.isArray(m.protocols) ? m.protocols.map((p) => String(p)) : [];
    entries.push({
      name: str(m.name, segs.at(-1) ?? ""),
      version: str(m.version),
      description: str(m.description),
      tier: str(m.tier),
      domain: str(m.domain),
      category: str(m.category),
      protocols,
      auth: str(auth?.method, "none"),
      toolCount: tools.length,
      available: m.available === !0,
      group,
      bucket: segs.length >= 3 ? segs[1] : "",
      path: rel
    });
  }
  entries.sort((a, b) => a.name.localeCompare(b.name));
  skipped.sort();
  return { entries, skipped };
}
function today() {
  return new Date().toISOString().slice(0, 10);
}
function renderCatalog(entries, generated) {
  return JSON.stringify({ schema: "boj-site-catalog/v1", generated, registry: REGISTRY, cartridges: entries }, null, 2) + `
`;
}
function renderIndex(html, total) {
  return html.replace(/(<title>BoJ Cartridge Registry \u2014 )\d+( open-source MCP cartridges<\/title>)/, `$1${total}$2`).replace(/(<meta name="description" content="Canonical registry of )\d+( open-source MCP cartridges)/, `$1${total}$2`).replace(/(<meta property="og:title" content="BoJ Cartridge Registry \u2014 )\d+( open-source MCP cartridges")/, `$1${total}$2`).replace(/(<meta property="og:description" content="Canonical registry of )\d+( open-source MCP cartridges)/, `$1${total}$2`).replace(/(<strong>)\d+( open-source MCP cartridges<\/strong>)/, `$1${total}$2`).replace(/(<span id="total-count">)\d+(<\/span>)/, `$1${total}$2`);
}
async function main() {
  const check = process.argv.slice(2).includes("--check"), { entries, skipped } = await collect(), oldCatalogRaw = await readTextFile(CATALOG_PATH).catch(() => "");
  let generated = today();
  try {
    const prev = JSON.parse(oldCatalogRaw);
    if (renderCatalog(prev.cartridges ?? [], "") === renderCatalog(entries, "") && typeof prev.generated === "string")
      generated = prev.generated;
  } catch {}
  const newCatalog = renderCatalog(entries, generated), oldIndex = await readTextFile(INDEX_PATH), newIndex = renderIndex(oldIndex, entries.length), catalogStale = newCatalog !== oldCatalogRaw, indexStale = newIndex !== oldIndex;
  if (check) {
    if (catalogStale || indexStale) {
      if (catalogStale)
        console.error("site/catalog.json is out of date");
      if (indexStale)
        console.error("site/index.html cartridge count is out of date");
      console.error("run `just catalog` and commit the result");
      process.exit(1);
    }
    console.log(`catalogue up to date \u2014 ${entries.length} cartridges`);
    return;
  }
  if (catalogStale)
    await writeTextFile(CATALOG_PATH, newCatalog);
  if (indexStale)
    await writeTextFile(INDEX_PATH, newIndex);
  console.log(`site/catalog.json: ${entries.length} cartridges (generated ${generated})`);
  for (const s of skipped)
    console.log(`  excluded (template, not installable): ${s}`);
  console.log(catalogStale ? "  catalog.json rewritten" : "  catalog.json already current");
  console.log(indexStale ? "  index.html counts rewritten" : "  index.html counts already current");
}
if (import.meta.main)
  await main();
