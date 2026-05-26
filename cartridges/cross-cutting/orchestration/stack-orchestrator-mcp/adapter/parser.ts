// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)
//
// Port of polystack/poly-orchestrator-lsp/lib/orchestrator/stack_parser.ex.
// Original module: PolyOrchestrator.Orchestrator.StackParser.
//
// Responsibilities:
// - TOML parsing + structure validation
// - Variable interpolation (${var}, ${env:VAR})
// - Component dependency graph extraction
// - Security policy extraction

import { parse as parseToml } from "jsr:@std/toml@1.0.2";
import type {
  Component,
  SecurityPolicies,
  Stack,
  Result,
} from "./types.ts";
import { err, ok } from "./types.ts";

export interface DependencyGraph {
  vertices: Map<string, Component>;
  edges: Array<[string, string]>;
}

/** Parse a stack.compose.toml from a filesystem path. */
export async function parseFile(path: string): Promise<Result<Stack>> {
  let content: string;
  try {
    content = await Deno.readTextFile(path);
  } catch (e) {
    return err(`File read error: ${(e as Error).message}`);
  }
  return parseString(content);
}

/** Parse stack.compose.toml content from a string. */
export function parseString(content: string): Result<Stack> {
  let raw: Record<string, unknown>;
  try {
    raw = parseToml(content) as Record<string, unknown>;
  } catch (e) {
    return err(`TOML parse error: ${(e as Error).message}`);
  }

  const structureResult = validateStructure(raw);
  if (!structureResult.ok) return structureResult;

  return interpolateVariables(structureResult.value);
}

/** Validate stack structure against the expected schema. */
export function validateStructure(toml: Record<string, unknown>): Result<Stack> {
  const metadataResult = validateMetadata(toml.metadata);
  if (!metadataResult.ok) return metadataResult;

  const componentsResult = validateComponents(toml.components);
  if (!componentsResult.ok) return componentsResult;

  const securityResult = validateSecurity(toml.security);
  if (!securityResult.ok) return securityResult;

  return ok(toml as unknown as Stack);
}

function validateMetadata(metadata: unknown): Result<true> {
  if (metadata == null) return err("Missing metadata section");
  if (typeof metadata !== "object") return err("Metadata must be a table");
  const m = metadata as Record<string, unknown>;
  const required = ["version", "name"];
  const missing = required.filter((k) => !(k in m));
  if (missing.length > 0) {
    return err(`Missing required metadata fields: ${missing.join(", ")}`);
  }
  return ok(true);
}

function validateComponents(components: unknown): Result<true> {
  if (components == null) return err("Missing components section");
  if (!Array.isArray(components)) return err("Components must be an array");
  if (components.length === 0) return err("No components defined");
  for (const component of components) {
    const r = validateComponent(component);
    if (!r.ok) return r;
  }
  return ok(true);
}

function validateComponent(component: unknown): Result<true> {
  if (typeof component !== "object" || component == null) {
    return err("Component must be a table");
  }
  const c = component as Record<string, unknown>;
  const required = ["id", "type", "lsp_server"];
  const missing = required.filter((k) => !(k in c));
  if (missing.length > 0) {
    const id = c.id ?? "<no-id>";
    return err(`Component ${id}: missing ${missing.join(", ")}`);
  }
  return ok(true);
}

function validateSecurity(_security: unknown): Result<true> {
  // Security section is optional.
  return ok(true);
}

/**
 * Interpolate ${var} and ${env:VAR} placeholders throughout the stack.
 * Falls back to keeping the placeholder unchanged when the variable is
 * unresolved (same behaviour as the Elixir version).
 */
export function interpolateVariables(stack: Stack): Result<Stack> {
  const variables = buildVariableContext(stack);

  const interpolatedComponents = (stack.components ?? []).map((c) =>
    interpolateMap(c as unknown as Record<string, unknown>, variables) as unknown as Component
  );

  const interpolatedVerification = (stack.verification ?? []).map((v) =>
    interpolateMap(v as unknown as Record<string, unknown>, variables)
  );

  return ok({
    ...stack,
    components: interpolatedComponents,
    verification: interpolatedVerification,
  });
}

function buildVariableContext(stack: Stack): Map<string, string> {
  const orchestration = stack.orchestration ?? {};
  const declared = orchestration.variables ?? {};
  const ctx = new Map<string, string>(Object.entries(declared));
  // Expose environment variables under env: prefix.
  for (const [k, v] of Object.entries(Deno.env.toObject())) {
    ctx.set(`env:${k}`, v);
  }
  return ctx;
}

function interpolateMap(
  m: Record<string, unknown>,
  variables: Map<string, string>,
): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(m)) {
    out[k] = interpolateValue(v, variables);
  }
  return out;
}

function interpolateValue(
  value: unknown,
  variables: Map<string, string>,
): unknown {
  if (typeof value === "string") {
    return value.replace(/\$\{([^}]+)\}/g, (_, varName: string) => {
      return variables.get(varName) ?? `\${${varName}}`;
    });
  }
  if (Array.isArray(value)) {
    return value.map((v) => interpolateValue(v, variables));
  }
  if (value !== null && typeof value === "object") {
    return interpolateMap(value as Record<string, unknown>, variables);
  }
  return value;
}

/** Build the dependency graph from the components list. */
export function extractDependencyGraph(stack: Stack): DependencyGraph {
  const components = stack.components ?? [];
  const vertices = new Map<string, Component>();
  const edges: Array<[string, string]> = [];

  for (const c of components) vertices.set(c.id, c);
  for (const c of components) {
    for (const dep of c.depends_on ?? []) edges.push([dep, c.id]);
  }

  return { vertices, edges };
}

/** Group components by their declared phase number. Default phase = 1. */
export function groupByPhase(stack: Stack): Map<number, Component[]> {
  const components = stack.components ?? [];
  const groups = new Map<number, Component[]>();
  for (const c of components) {
    const phase = c.phase ?? 1;
    if (!groups.has(phase)) groups.set(phase, []);
    groups.get(phase)!.push(c);
  }
  for (const list of groups.values()) list.sort((a, b) => a.id.localeCompare(b.id));
  return groups;
}

/** Extract the security policy block; absent keys map to safe defaults. */
export function extractSecurityPolicies(stack: Stack): SecurityPolicies {
  const s = stack.security ?? {};
  return {
    threat_model: s.threat_model,
    attack_surface_score: s.attack_surface_score,
    validated: s.validated ?? false,
    policies: s.policies ?? [],
    constraints: s.constraints ?? [],
  };
}
