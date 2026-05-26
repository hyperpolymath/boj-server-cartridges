// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  extractDependencyGraph,
  extractSecurityPolicies,
  groupByPhase,
  parseString,
  validateStructure,
} from "./parser.ts";

const MINIMAL_STACK = `
[metadata]
name = "test-stack"
version = "1.0.0"

[[components]]
id = "a"
type = "cloud.provision"
lsp_server = "cloud-lsp"

[[components]]
id = "b"
type = "container.build"
lsp_server = "container-lsp"
depends_on = ["a"]
`;

Deno.test("parseString — minimal valid stack succeeds", () => {
  const r = parseString(MINIMAL_STACK);
  assert(r.ok, `expected ok, got: ${!r.ok && r.error}`);
  assertEquals(r.value.metadata.name, "test-stack");
  assertEquals(r.value.components.length, 2);
});

Deno.test("parseString — missing metadata fails", () => {
  const r = parseString(`[[components]]\nid = "x"\ntype = "y"\nlsp_server = "z"\n`);
  assert(!r.ok);
  assertEquals(r.error, "Missing metadata section");
});

Deno.test("parseString — missing required metadata field fails", () => {
  const r = parseString(`[metadata]\nname = "x"\n\n[[components]]\nid="a"\ntype="t"\nlsp_server="s"\n`);
  assert(!r.ok);
  assert(r.error.includes("version"));
});

Deno.test("parseString — component missing lsp_server fails", () => {
  const r = parseString(`
[metadata]
name="x"
version="1.0.0"

[[components]]
id="a"
type="t"
`);
  assert(!r.ok);
  assert(r.error.includes("lsp_server"));
});

Deno.test("parseString — no components fails", () => {
  const r = parseString(`[metadata]\nname="x"\nversion="1.0.0"\n`);
  assert(!r.ok);
  assertEquals(r.error, "Missing components section");
});

Deno.test("validateStructure — accepts well-formed input", () => {
  const r = validateStructure({
    metadata: { name: "x", version: "1.0.0" },
    components: [{ id: "a", type: "t", lsp_server: "s" }],
  });
  assert(r.ok);
});

Deno.test("interpolation — variable substitution from orchestration.variables", () => {
  const stack = `
[metadata]
name = "x"
version = "1.0.0"

[orchestration.variables]
region = "eu-west-1"

[[components]]
id = "a"
type = "cloud.provision"
lsp_server = "cloud-lsp"

[components.config]
region = "\${region}"
`;
  const r = parseString(stack);
  assert(r.ok);
  const config = r.value.components[0].config as Record<string, unknown>;
  assertEquals(config.region, "eu-west-1");
});

Deno.test("interpolation — unknown variable left in place", () => {
  const stack = `
[metadata]
name = "x"
version = "1.0.0"

[[components]]
id = "a"
type = "cloud.provision"
lsp_server = "cloud-lsp"

[components.config]
endpoint = "\${unknown.var}"
`;
  const r = parseString(stack);
  assert(r.ok);
  const config = r.value.components[0].config as Record<string, unknown>;
  assertEquals(config.endpoint, "${unknown.var}");
});

Deno.test("extractDependencyGraph — vertices + edges", () => {
  const r = parseString(MINIMAL_STACK);
  assert(r.ok);
  const g = extractDependencyGraph(r.value);
  assertEquals(g.vertices.size, 2);
  assertEquals(g.edges.length, 1);
  assertEquals(g.edges[0], ["a", "b"]);
});

Deno.test("groupByPhase — defaults to phase 1, sorts by id", () => {
  const stack = `
[metadata]
name = "x"
version = "1.0.0"

[[components]]
id = "z"
type = "t"
lsp_server = "s"
phase = 2

[[components]]
id = "a"
type = "t"
lsp_server = "s"

[[components]]
id = "m"
type = "t"
lsp_server = "s"
`;
  const r = parseString(stack);
  assert(r.ok);
  const groups = groupByPhase(r.value);
  assertEquals(groups.size, 2);
  assertEquals(groups.get(1)!.map((c) => c.id), ["a", "m"]);
  assertEquals(groups.get(2)!.map((c) => c.id), ["z"]);
});

Deno.test("extractSecurityPolicies — empty section yields safe defaults", () => {
  const r = parseString(MINIMAL_STACK);
  assert(r.ok);
  const policies = extractSecurityPolicies(r.value);
  assertEquals(policies.validated, false);
  assertEquals(policies.policies, []);
  assertEquals(policies.constraints, []);
});

Deno.test("extractSecurityPolicies — populated section", () => {
  const stack = `
[metadata]
name = "x"
version = "1.0.0"

[security]
threat_model = "STRIDE"
attack_surface_score = 7
validated = true
policies = ["least-privilege"]
constraints = ["no-public-ingress"]

[[components]]
id = "a"
type = "t"
lsp_server = "s"
`;
  const r = parseString(stack);
  assert(r.ok);
  const policies = extractSecurityPolicies(r.value);
  assertEquals(policies.threat_model, "STRIDE");
  assertEquals(policies.attack_surface_score, 7);
  assertEquals(policies.validated, true);
  assertEquals(policies.policies, ["least-privilege"]);
});
