// SPDX-License-Identifier: MPL-2.0
import { test } from "bun:test";
import { ok as assert, deepStrictEqual as assertEquals } from "node:assert/strict";
import { extractDependencyGraph, parseString } from "./parser.js";
import {
  buildPhases,
  buildPlan,
  buildRollbackPlan,
  estimateDuration,
  identifyParallelComponents,
  topologicalSort,
  validateGraph
} from "./planner.js";
const LINEAR_STACK = `
[metadata]
name = "linear-stack"
version = "1.0.0"

[[components]]
id = "a"
type = "cloud.provision"
lsp_server = "cloud-lsp"

[[components]]
id = "b"
type = "database.provision"
lsp_server = "database-lsp"
depends_on = ["a"]

[[components]]
id = "c"
type = "container.build"
lsp_server = "container-lsp"
depends_on = ["b"]
`, DIAMOND_STACK = `
[metadata]
name = "diamond-stack"
version = "1.0.0"

[[components]]
id = "a"
type = "cloud.provision"
lsp_server = "cloud-lsp"

[[components]]
id = "b"
type = "database.provision"
lsp_server = "database-lsp"
depends_on = ["a"]

[[components]]
id = "c"
type = "observability.setup"
lsp_server = "observe-lsp"
depends_on = ["a"]

[[components]]
id = "d"
type = "container.build"
lsp_server = "container-lsp"
depends_on = ["b", "c"]
`, CYCLE_STACK = `
[metadata]
name = "cycle-stack"
version = "1.0.0"

[[components]]
id = "a"
type = "t"
lsp_server = "s"
depends_on = ["b"]

[[components]]
id = "b"
type = "t"
lsp_server = "s"
depends_on = ["a"]
`;
test("topologicalSort \u2014 linear chain a\u2192b\u2192c", () => {
  const stack = parseString(LINEAR_STACK);
  assert(stack.ok);
  const g = extractDependencyGraph(stack.value), r = topologicalSort(g);
  assert(r.ok);
  assertEquals(r.value, ["a", "b", "c"]);
});
test("topologicalSort \u2014 diamond produces valid linearization", () => {
  const stack = parseString(DIAMOND_STACK);
  assert(stack.ok);
  const g = extractDependencyGraph(stack.value), r = topologicalSort(g);
  assert(r.ok);
  assertEquals(r.value[0], "a");
  assertEquals(r.value[3], "d");
  const positions = new Map(r.value.map((id, i) => [id, i]));
  assert(positions.get("b") > positions.get("a"));
  assert(positions.get("c") > positions.get("a"));
  assert(positions.get("d") > positions.get("b"));
  assert(positions.get("d") > positions.get("c"));
});
test("validateGraph \u2014 flags cycles", () => {
  const stack = parseString(CYCLE_STACK);
  assert(stack.ok);
  const g = extractDependencyGraph(stack.value), r = validateGraph(g);
  assert(!r.ok);
  assert(r.error.includes("Cyclic"));
});
test("validateGraph \u2014 flags dangling dependency edges", () => {
  const stack = parseString(LINEAR_STACK);
  assert(stack.ok);
  const g = extractDependencyGraph(stack.value);
  g.edges.push(["a", "ghost"]);
  const r = validateGraph(g);
  assert(!r.ok);
  assert(r.error.includes("unknown component"));
});
test("buildPhases \u2014 diamond yields one phase, multiple parallel groups", () => {
  const stack = parseString(DIAMOND_STACK);
  assert(stack.ok);
  const g = extractDependencyGraph(stack.value), sorted = topologicalSort(g);
  assert(sorted.ok);
  const phases = buildPhases(sorted.value, stack.value);
  assert(phases.ok);
  assertEquals(phases.value.length, 1);
  const phase = phases.value[0];
  assertEquals(phase.parallel[0], ["a"]);
  assertEquals(phase.parallel[1].sort(), ["b", "c"]);
  assertEquals(phase.parallel[2], ["d"]);
});
test("identifyParallelComponents \u2014 independent components bundle together", () => {
  const c = (id, deps = []) => ({
    id,
    type: "t",
    lsp_server: "s",
    depends_on: deps
  }), groups = identifyParallelComponents([c("a"), c("b"), c("c")]);
  assertEquals(groups, [["a", "b", "c"]]);
});
test("identifyParallelComponents \u2014 chained deps split into sequential groups", () => {
  const c = (id, deps = []) => ({
    id,
    type: "t",
    lsp_server: "s",
    depends_on: deps
  }), groups = identifyParallelComponents([
    c("a"),
    c("b", ["a"]),
    c("c", ["b"])
  ]);
  assertEquals(groups, [["a"], ["b"], ["c"]]);
});
test("buildPlan \u2014 end-to-end for linear stack", () => {
  const stack = parseString(LINEAR_STACK);
  assert(stack.ok);
  const r = buildPlan(stack.value);
  assert(r.ok);
  assertEquals(r.value.stack_id, "linear-stack");
  assertEquals(r.value.phases.length, 1);
  assertEquals(r.value.phases[0].components.length, 3);
  const servers = r.value.phases[0].components.map((c) => c.lsp_server).sort();
  assertEquals(servers, ["cloud-lsp", "container-lsp", "database-lsp"]);
});
test("buildPlan \u2014 fails on cycle", () => {
  const stack = parseString(CYCLE_STACK);
  assert(stack.ok);
  const r = buildPlan(stack.value);
  assert(!r.ok);
  assert(r.error.includes("Cyclic"));
});
test("buildRollbackPlan \u2014 reverses phase order + negates phase numbers", () => {
  const stack = parseString(LINEAR_STACK);
  assert(stack.ok);
  const plan = buildPlan(stack.value);
  assert(plan.ok);
  const rollback = buildRollbackPlan(plan.value);
  assertEquals(rollback.phases.length, 1);
  assertEquals(rollback.phases[0].phase, -1);
  assertEquals(rollback.phases[0].components.map((c) => c.id), ["c", "b", "a"]);
});
test("estimateDuration \u2014 applies per-type heuristics", () => {
  const stack = parseString(LINEAR_STACK);
  assert(stack.ok);
  const plan = buildPlan(stack.value);
  assert(plan.ok);
  const est = estimateDuration(plan.value);
  assertEquals(est.total_ms, 660000);
  assert(est.parallel_factor >= 1);
});
