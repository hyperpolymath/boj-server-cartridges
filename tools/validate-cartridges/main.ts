// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)
//
// Cartridge-manifest validator. Walks cartridges/ and checks each
// cartridge.json against the canonical schema in ../../schemas/cartridge-v1.json.
//
// Modes:
//   --audit (default): print a per-manifest report; exit 0 even on validation
//                      failure. Use during the drift-inventory phase.
//   --strict:          exit non-zero if any manifest fails validation. Use
//                      once drift is fixed.

import { walk } from "jsr:@std/fs@1/walk";
import { fromFileUrl, join } from "jsr:@std/path@1";

type JsonValue = string | number | boolean | null | JsonValue[] | { [k: string]: JsonValue };
type Schema = { [k: string]: JsonValue };

interface ValidationIssue {
  path: string;
  message: string;
}

const ROOT = fromFileUrl(new URL("../..", import.meta.url));
const SCHEMA_PATH = join(ROOT, "schemas", "cartridge-v1.json");
const CARTRIDGES_DIR = join(ROOT, "cartridges");

function typeOfJson(v: JsonValue): string {
  if (v === null) return "null";
  if (Array.isArray(v)) return "array";
  return typeof v;
}

function matchesType(v: JsonValue, type: JsonValue): boolean {
  if (Array.isArray(type)) {
    return type.some((t) => matchesType(v, t));
  }
  if (typeof type !== "string") return true;
  const t = typeOfJson(v);
  if (type === "integer") return t === "number" && Number.isInteger(v);
  return t === type;
}

function validate(
  value: JsonValue,
  schema: Schema,
  path: string,
  issues: ValidationIssue[],
): void {
  if (schema.type !== undefined && !matchesType(value, schema.type)) {
    issues.push({ path, message: `expected type ${JSON.stringify(schema.type)} but got ${typeOfJson(value)}` });
    return;
  }
  if (Array.isArray(schema.enum) && !schema.enum.some((e) => JSON.stringify(e) === JSON.stringify(value))) {
    issues.push({ path, message: `value ${JSON.stringify(value)} not in enum ${JSON.stringify(schema.enum)}` });
  }
  if (typeof schema.pattern === "string" && typeof value === "string") {
    try {
      if (!new RegExp(schema.pattern).test(value)) {
        issues.push({ path, message: `value ${JSON.stringify(value)} does not match pattern /${schema.pattern}/` });
      }
    } catch (e) {
      issues.push({ path, message: `bad pattern in schema: ${(e as Error).message}` });
    }
  }
  if (typeof value === "object" && value !== null && !Array.isArray(value)) {
    if (Array.isArray(schema.required)) {
      for (const req of schema.required) {
        if (typeof req === "string" && !(req in value)) {
          issues.push({ path: path ? `${path}.${req}` : req, message: "required field missing" });
        }
      }
    }
    if (schema.properties && typeof schema.properties === "object" && !Array.isArray(schema.properties)) {
      const props = schema.properties as Record<string, Schema>;
      for (const [k, v] of Object.entries(value)) {
        if (props[k]) {
          validate(v, props[k], path ? `${path}.${k}` : k, issues);
        }
      }
    }
  }
  if (Array.isArray(value) && schema.items && typeof schema.items === "object" && !Array.isArray(schema.items)) {
    for (let i = 0; i < value.length; i++) {
      validate(value[i], schema.items as Schema, `${path}[${i}]`, issues);
    }
    if (typeof schema.minItems === "number" && value.length < schema.minItems) {
      issues.push({ path, message: `array length ${value.length} below minItems ${schema.minItems}` });
    }
  }
}

async function main() {
  const args = Deno.args;
  const strict = args.includes("--strict");
  const verbose = args.includes("--verbose");

  const schemaText = await Deno.readTextFile(SCHEMA_PATH);
  const schema = JSON.parse(schemaText) as Schema;

  const results: { file: string; issues: ValidationIssue[] }[] = [];
  for await (const entry of walk(CARTRIDGES_DIR, { exts: [".json"], includeDirs: false })) {
    if (!entry.name.endsWith("cartridge.json")) continue;
    const text = await Deno.readTextFile(entry.path);
    let parsed: JsonValue;
    try {
      parsed = JSON.parse(text);
    } catch (e) {
      results.push({
        file: entry.path,
        issues: [{ path: "", message: `JSON parse error: ${(e as Error).message}` }],
      });
      continue;
    }
    const issues: ValidationIssue[] = [];
    validate(parsed, schema, "", issues);
    results.push({ file: entry.path, issues });
  }

  results.sort((a, b) => a.file.localeCompare(b.file));

  const total = results.length;
  const failing = results.filter((r) => r.issues.length > 0);
  const passing = total - failing.length;

  const issueCounts = new Map<string, number>();
  for (const r of failing) {
    for (const i of r.issues) {
      const key = `${i.path}: ${i.message.split(" not in enum")[0].split(" does not match")[0]}`;
      issueCounts.set(key, (issueCounts.get(key) ?? 0) + 1);
    }
  }
  const topIssues = [...issueCounts.entries()].sort((a, b) => b[1] - a[1]);

  console.log(`# Cartridge manifest validation report`);
  console.log(`Schema: schemas/cartridge-v1.json`);
  console.log(`Manifests: ${total} total / ${passing} passing / ${failing.length} failing`);
  console.log(``);
  console.log(`## Top recurring issues`);
  for (const [key, count] of topIssues.slice(0, 15)) {
    console.log(`- ${count}× ${key}`);
  }
  if (verbose) {
    console.log(``);
    console.log(`## Per-manifest failures`);
    for (const r of failing) {
      console.log(``);
      console.log(`### ${r.file.replace(ROOT + "/", "")}`);
      for (const i of r.issues) {
        console.log(`- \`${i.path || "<root>"}\` — ${i.message}`);
      }
    }
  }

  if (strict && failing.length > 0) {
    console.error(`\nstrict: ${failing.length} manifest(s) failed validation`);
    Deno.exit(1);
  }
}

await main();
