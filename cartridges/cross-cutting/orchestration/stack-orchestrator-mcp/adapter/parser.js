// SPDX-License-Identifier: MPL-2.0
import { readTextFile } from "../../../../lib/files.js";
const parseToml = Bun.TOML.parse;
import { err, ok } from "./types.js";
export async function parseFile(path) {
  let content;
  try {
    content = await readTextFile(path);
  } catch (e) {
    return err(`File read error: ${e.message}`);
  }
  return parseString(content);
}
export function parseString(content) {
  let raw;
  try {
    raw = parseToml(content);
  } catch (e) {
    return err(`TOML parse error: ${e.message}`);
  }
  const structureResult = validateStructure(raw);
  if (!structureResult.ok)
    return structureResult;
  return interpolateVariables(structureResult.value);
}
export function validateStructure(toml) {
  const metadataResult = validateMetadata(toml.metadata);
  if (!metadataResult.ok)
    return metadataResult;
  const componentsResult = validateComponents(toml.components);
  if (!componentsResult.ok)
    return componentsResult;
  const securityResult = validateSecurity(toml.security);
  if (!securityResult.ok)
    return securityResult;
  return ok(toml);
}
function validateMetadata(metadata) {
  if (metadata == null)
    return err("Missing metadata section");
  if (typeof metadata !== "object")
    return err("Metadata must be a table");
  const m = metadata, missing = ["version", "name"].filter((k) => !(k in m));
  if (missing.length > 0)
    return err(`Missing required metadata fields: ${missing.join(", ")}`);
  return ok(!0);
}
function validateComponents(components) {
  if (components == null)
    return err("Missing components section");
  if (!Array.isArray(components))
    return err("Components must be an array");
  if (components.length === 0)
    return err("No components defined");
  for (const component of components) {
    const r = validateComponent(component);
    if (!r.ok)
      return r;
  }
  return ok(!0);
}
function validateComponent(component) {
  if (typeof component !== "object" || component == null)
    return err("Component must be a table");
  const c = component, missing = ["id", "type", "lsp_server"].filter((k) => !(k in c));
  if (missing.length > 0) {
    const id = c.id ?? "<no-id>";
    return err(`Component ${id}: missing ${missing.join(", ")}`);
  }
  return ok(!0);
}
function validateSecurity(_security) {
  return ok(!0);
}
export function interpolateVariables(stack) {
  const variables = buildVariableContext(stack), interpolatedComponents = (stack.components ?? []).map((c) => interpolateMap(c, variables)), interpolatedVerification = (stack.verification ?? []).map((v) => interpolateMap(v, variables));
  return ok({
    ...stack,
    components: interpolatedComponents,
    verification: interpolatedVerification
  });
}
function buildVariableContext(stack) {
  const declared = (stack.orchestration ?? {}).variables ?? {}, ctx = new Map(Object.entries(declared));
  for (const [k, v] of Object.entries(process.env))
    ctx.set(`env:${k}`, v);
  return ctx;
}
function interpolateMap(m, variables) {
  const out = {};
  for (const [k, v] of Object.entries(m))
    out[k] = interpolateValue(v, variables);
  return out;
}
function interpolateValue(value, variables) {
  if (typeof value === "string")
    return value.replace(/\$\{([^}]+)\}/g, (_, varName) => {
      return variables.get(varName) ?? `\${${varName}}`;
    });
  if (Array.isArray(value))
    return value.map((v) => interpolateValue(v, variables));
  if (value !== null && typeof value === "object")
    return interpolateMap(value, variables);
  return value;
}
export function extractDependencyGraph(stack) {
  const components = stack.components ?? [], vertices = new Map, edges = [];
  for (const c of components)
    vertices.set(c.id, c);
  for (const c of components)
    for (const dep of c.depends_on ?? [])
      edges.push([dep, c.id]);
  return { vertices, edges };
}
export function groupByPhase(stack) {
  const components = stack.components ?? [], groups = new Map;
  for (const c of components) {
    const phase = c.phase ?? 1;
    if (!groups.has(phase))
      groups.set(phase, []);
    groups.get(phase).push(c);
  }
  for (const list of groups.values())
    list.sort((a, b) => a.id.localeCompare(b.id));
  return groups;
}
export function extractSecurityPolicies(stack) {
  const s = stack.security ?? {};
  return {
    threat_model: s.threat_model,
    attack_surface_score: s.attack_surface_score,
    validated: s.validated ?? !1,
    policies: s.policies ?? [],
    constraints: s.constraints ?? []
  };
}
