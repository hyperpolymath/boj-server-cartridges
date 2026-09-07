// SPDX-License-Identifier: MPL-2.0
import { test } from "bun:test";
import { ok as assert, deepStrictEqual as assertEquals } from "node:assert/strict";
import {
  extractDependencyGraph,
  extractSecurityPolicies,
  groupByPhase,
  parseString,
  validateStructure
} from "./parser.js";
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
test("parseString \u2014 minimal valid stack succeeds", () => {
  const r = parseString(MINIMAL_STACK);
  assert(r.ok, `expected ok, got: ${!r.ok && r.error}`);
  assertEquals(r.value.metadata.name, "test-stack");
  assertEquals(r.value.components.length, 2);
});
test("parseString \u2014 missing metadata fails", () => {
  const r = parseString(`[[components]]
id = "x"
type = "y"
lsp_server = "z"
`);
  assert(!r.ok);
  assertEquals(r.error, "Missing metadata section");
});
test("parseString \u2014 missing required metadata field fails", () => {
  const r = parseString(`[metadata]
name = "x"

[[components]]
id="a"
type="t"
lsp_server="s"
`);
  assert(!r.ok);
  assert(r.error.includes("version"));
});
test("parseString \u2014 component missing lsp_server fails", () => {
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
test("parseString \u2014 no components fails", () => {
  const r = parseString(`[metadata]
name="x"
version="1.0.0"
`);
  assert(!r.ok);
  assertEquals(r.error, "Missing components section");
});
test("validateStructure \u2014 accepts well-formed input", () => {
  const r = validateStructure({
    metadata: { name: "x", version: "1.0.0" },
    components: [{ id: "a", type: "t", lsp_server: "s" }]
  });
  assert(r.ok);
});
test("interpolation \u2014 variable substitution from orchestration.variables", () => {
  const r = parseString(`
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
`);
  assert(r.ok);
  const config = r.value.components[0].config;
  assertEquals(config.region, "eu-west-1");
});
test("interpolation \u2014 unknown variable left in place", () => {
  const r = parseString(`
[metadata]
name = "x"
version = "1.0.0"

[[components]]
id = "a"
type = "cloud.provision"
lsp_server = "cloud-lsp"

[components.config]
endpoint = "\${unknown.var}"
`);
  assert(r.ok);
  const config = r.value.components[0].config;
  assertEquals(config.endpoint, "${unknown.var}");
});
test("extractDependencyGraph \u2014 vertices + edges", () => {
  const r = parseString(MINIMAL_STACK);
  assert(r.ok);
  const g = extractDependencyGraph(r.value);
  assertEquals(g.vertices.size, 2);
  assertEquals(g.edges.length, 1);
  assertEquals(g.edges[0], ["a", "b"]);
});
test("groupByPhase \u2014 defaults to phase 1, sorts by id", () => {
  const r = parseString(`
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
`);
  assert(r.ok);
  const groups = groupByPhase(r.value);
  assertEquals(groups.size, 2);
  assertEquals(groups.get(1).map((c) => c.id), ["a", "m"]);
  assertEquals(groups.get(2).map((c) => c.id), ["z"]);
});
test("extractSecurityPolicies \u2014 empty section yields safe defaults", () => {
  const r = parseString(MINIMAL_STACK);
  assert(r.ok);
  const policies = extractSecurityPolicies(r.value);
  assertEquals(policies.validated, !1);
  assertEquals(policies.policies, []);
  assertEquals(policies.constraints, []);
});
test("extractSecurityPolicies \u2014 populated section", () => {
  const r = parseString(`
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
`);
  assert(r.ok);
  const policies = extractSecurityPolicies(r.value);
  assertEquals(policies.threat_model, "STRIDE");
  assertEquals(policies.attack_surface_score, 7);
  assertEquals(policies.validated, !0);
  assertEquals(policies.policies, ["least-privilege"]);
});
