// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)
//
// Validator unit tests. Run with: `deno task test` from this directory.

import { assertEquals, assertGreater } from "jsr:@std/assert@1";

const SCHEMA = {
  type: "object",
  required: ["name", "category", "auth", "protocols"],
  properties: {
    name: { type: "string", pattern: "^[a-z0-9-]+-(mcp|lsp)$" },
    category: { type: "string", enum: ["domain", "cross-cutting", "template"] },
    auth: {
      type: "object",
      required: ["method"],
      properties: {
        method: { type: "string", enum: ["none", "api-key", "oauth2", "vault"] },
      },
    },
    protocols: {
      type: "array",
      items: { type: "string", enum: ["MCP", "LSP", "REST"] },
      minItems: 1,
    },
  },
};

type JsonValue = string | number | boolean | null | JsonValue[] | { [k: string]: JsonValue };
type Schema = { [k: string]: JsonValue };
interface ValidationIssue {
  path: string;
  message: string;
}

function typeOfJson(v: JsonValue): string {
  if (v === null) return "null";
  if (Array.isArray(v)) return "array";
  return typeof v;
}
function matchesType(v: JsonValue, type: JsonValue): boolean {
  if (Array.isArray(type)) return type.some((t) => matchesType(v, t));
  if (typeof type !== "string") return true;
  const t = typeOfJson(v);
  if (type === "integer") return t === "number" && Number.isInteger(v);
  return t === type;
}
function validate(value: JsonValue, schema: Schema, path: string, issues: ValidationIssue[]): void {
  if (schema.type !== undefined && !matchesType(value, schema.type)) {
    issues.push({ path, message: `expected type ${JSON.stringify(schema.type)} but got ${typeOfJson(value)}` });
    return;
  }
  if (Array.isArray(schema.enum) && !schema.enum.some((e) => JSON.stringify(e) === JSON.stringify(value))) {
    issues.push({ path, message: `value ${JSON.stringify(value)} not in enum ${JSON.stringify(schema.enum)}` });
  }
  if (typeof schema.pattern === "string" && typeof value === "string") {
    if (!new RegExp(schema.pattern).test(value)) {
      issues.push({ path, message: `value ${JSON.stringify(value)} does not match pattern /${schema.pattern}/` });
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
        if (props[k]) validate(v, props[k], path ? `${path}.${k}` : k, issues);
      }
    }
  }
  if (Array.isArray(value) && schema.items && typeof schema.items === "object" && !Array.isArray(schema.items)) {
    for (let i = 0; i < value.length; i++) validate(value[i], schema.items as Schema, `${path}[${i}]`, issues);
    if (typeof schema.minItems === "number" && value.length < schema.minItems) {
      issues.push({ path, message: `array length ${value.length} below minItems ${schema.minItems}` });
    }
  }
}

Deno.test("valid manifest produces no issues", () => {
  const m = {
    name: "example-mcp",
    category: "domain",
    auth: { method: "none" },
    protocols: ["MCP", "REST"],
  };
  const issues: ValidationIssue[] = [];
  validate(m, SCHEMA, "", issues);
  assertEquals(issues, []);
});

Deno.test("missing required top-level field surfaces", () => {
  const m = { name: "example-mcp", auth: { method: "none" }, protocols: ["MCP"] };
  const issues: ValidationIssue[] = [];
  validate(m, SCHEMA, "", issues);
  assertEquals(issues.length, 1);
  assertEquals(issues[0].path, "category");
  assertEquals(issues[0].message, "required field missing");
});

Deno.test("missing required nested field surfaces with dotted path", () => {
  const m = { name: "example-mcp", category: "domain", auth: {}, protocols: ["MCP"] };
  const issues: ValidationIssue[] = [];
  validate(m, SCHEMA, "", issues);
  assertEquals(issues.length, 1);
  assertEquals(issues[0].path, "auth.method");
});

Deno.test("enum violation reports the offending value", () => {
  const m = {
    name: "example-mcp",
    category: "domain",
    auth: { method: "bearer_token" },
    protocols: ["MCP"],
  };
  const issues: ValidationIssue[] = [];
  validate(m, SCHEMA, "", issues);
  assertGreater(issues.length, 0);
  const enumIssue = issues.find((i) => i.path === "auth.method");
  assertEquals(typeof enumIssue, "object");
  assertEquals(enumIssue!.message.includes("bearer_token"), true);
});

Deno.test("pattern violation reports", () => {
  const m = {
    name: "ExampleMCP",
    category: "domain",
    auth: { method: "none" },
    protocols: ["MCP"],
  };
  const issues: ValidationIssue[] = [];
  validate(m, SCHEMA, "", issues);
  const patternIssue = issues.find((i) => i.path === "name");
  assertEquals(typeof patternIssue, "object");
  assertEquals(patternIssue!.message.includes("does not match pattern"), true);
});

Deno.test("array minItems violation reports", () => {
  const m = {
    name: "example-mcp",
    category: "domain",
    auth: { method: "none" },
    protocols: [],
  };
  const issues: ValidationIssue[] = [];
  validate(m, SCHEMA, "", issues);
  const minItemsIssue = issues.find((i) => i.path === "protocols" && i.message.includes("minItems"));
  assertEquals(typeof minItemsIssue, "object");
});

Deno.test("type mismatch short-circuits descent", () => {
  const m = { name: 42, category: "domain", auth: { method: "none" }, protocols: ["MCP"] };
  const issues: ValidationIssue[] = [];
  validate(m as unknown as Record<string, JsonValue>, SCHEMA, "", issues);
  const typeIssue = issues.find((i) => i.path === "name" && i.message.includes("expected type"));
  assertEquals(typeof typeIssue, "object");
});
