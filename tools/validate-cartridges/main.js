// SPDX-License-Identifier: MPL-2.0
import Ajv2020 from "ajv/dist/2020.js";
import addFormats from "ajv-formats";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";
import { join, relative } from "node:path";
import { walk, readTextFile } from "../lib/files.js";

const ROOT = fileURLToPath(new URL("../..", import.meta.url));
const schemaBytes = await readTextFile(join(ROOT, "schemas/cartridge-v1.json"));
const pin = Bun.TOML.parse(await readTextFile(join(ROOT, "schemas/PINNED-SHA")));
if (!/^[a-f0-9]{64}$/.test(pin.content_sha256) ||
    createHash("sha256").update(schemaBytes).digest("hex") !== pin.content_sha256) {
  throw new Error("Canonical cartridge schema does not match PINNED-SHA");
}
const ajv = new Ajv2020({ allErrors: true, strict: true, allowUnionTypes: true });
addFormats(ajv);
const check = ajv.compile(JSON.parse(schemaBytes));

export function validateManifest(manifest) {
  return check(manifest) ? [] : structuredClone(check.errors);
}

export async function validateTree(root = join(ROOT, "cartridges")) {
  const results = [];
  const names = new Set();
  for await (const entry of walk(root, { includeDirs: false, match: [/(?:^|\/)cartridge\.json$/] })) {
    let errors;
    try {
      const manifest = JSON.parse(await readTextFile(entry.path));
      errors = validateManifest(manifest);
      if (names.has(manifest.name)) errors.push({ message: "duplicate cartridge name" });
      names.add(manifest.name);
    } catch (error) {
      errors = [{ message: error.message }];
    }
    results.push({ path: relative(root, entry.path), errors });
  }
  if (results.length === 0) throw new Error(`No cartridge manifests found under ${root}`);
  return results;
}

if (import.meta.main) {
  const results = await validateTree(process.env.BOJ_VALIDATION_ROOT);
  const failures = results.filter((r) => r.errors.length);
  for (const failure of failures) console.error(JSON.stringify(failure));
  console.log(`${results.length} manifests checked; ${failures.length} invalid`);
  // Audit mode is explicitly informational; all other invocations fail closed.
  if (failures.length && !process.argv.includes("--audit")) process.exitCode = 1;
}
