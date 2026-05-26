// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

import { assert, assertEquals } from "jsr:@std/assert@1";
import { extractDependencyGraph, parseString } from "./parser.ts";
import {
  buildPhases,
  buildPlan,
  buildRollbackPlan,
  estimateDuration,
  identifyParallelComponents,
  topologicalSort,
  validateGraph,
} from "./planner.ts";

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
`;

const DIAMOND_STACK = `
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
`;

const CYCLE_STACK = `
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

Deno.test("topologicalSort — linear chain a→b→c", () => {
  const stack = parseString(LINEAR_STACK);
  assert(stack.ok);
  const g = extractDependencyGraph(stack.value);
  const r = topologicalSort(g);
  assert(r.ok);
  assertEquals(r.value, ["a", "b", "c"]);
});

Deno.test("topologicalSort — diamond produces valid linearization", () => {
  const stack = parseString(DIAMOND_STACK);
  assert(stack.ok);
  const g = extractDependencyGraph(stack.value);
  const r = topologicalSort(g);
  assert(r.ok);
  // a must come first; d must come last.
  assertEquals(r.value[0], "a");
  assertEquals(r.value[3], "d");
  // b and c must both come after a, before d.
  const positions = new Map(r.value.map((id, i) => [id, i]));
  assert(positions.get("b")! > positions.get("a")!);
  assert(positions.get("c")! > positions.get("a")!);
  assert(positions.get("d")! > positions.get("b")!);
  assert(positions.get("d")! > positions.get("c")!);
});

Deno.test("validateGraph — flags cycles", () => {
  const stack = parseString(CYCLE_STACK);
  assert(stack.ok);
  const g = extractDependencyGraph(stack.value);
  const r = validateGraph(g);
  assert(!r.ok);
  assert(r.error.includes("Cyclic"));
});

Deno.test("validateGraph — flags dangling dependency edges", () => {
  const stack = parseString(LINEAR_STACK);
  assert(stack.ok);
  const g = extractDependencyGraph(stack.value);
  g.edges.push(["a", "ghost"]);
  const r = validateGraph(g);
  assert(!r.ok);
  assert(r.error.includes("unknown component"));
});

Deno.test("buildPhases — diamond yields one phase, multiple parallel groups", () => {
  const stack = parseString(DIAMOND_STACK);
  assert(stack.ok);
  const g = extractDependencyGraph(stack.value);
  const sorted = topologicalSort(g);
  assert(sorted.ok);
  const phases = buildPhases(sorted.value, stack.value);
  assert(phases.ok);
  assertEquals(phases.value.length, 1);
  const phase = phases.value[0];
  // a must launch alone, b+c can run in parallel, then d alone.
  assertEquals(phase.parallel[0], ["a"]);
  assertEquals(phase.parallel[1].sort(), ["b", "c"]);
  assertEquals(phase.parallel[2], ["d"]);
});

Deno.test("identifyParallelComponents — independent components bundle together", () => {
  const c = (id: string, deps: string[] = []) => ({
    id,
    type: "t",
    lsp_server: "s",
    depends_on: deps,
  });
  const groups = identifyParallelComponents([c("a"), c("b"), c("c")]);
  assertEquals(groups, [["a", "b", "c"]]);
});

Deno.test("identifyParallelComponents — chained deps split into sequential groups", () => {
  const c = (id: string, deps: string[] = []) => ({
    id,
    type: "t",
    lsp_server: "s",
    depends_on: deps,
  });
  const groups = identifyParallelComponents([
    c("a"),
    c("b", ["a"]),
    c("c", ["b"]),
  ]);
  assertEquals(groups, [["a"], ["b"], ["c"]]);
});

Deno.test("buildPlan — end-to-end for linear stack", () => {
  const stack = parseString(LINEAR_STACK);
  assert(stack.ok);
  const r = buildPlan(stack.value);
  assert(r.ok);
  assertEquals(r.value.stack_id, "linear-stack");
  assertEquals(r.value.phases.length, 1);
  assertEquals(r.value.phases[0].components.length, 3);
  // Components carry through lsp_server routing.
  const servers = r.value.phases[0].components.map((c) => c.lsp_server).sort();
  assertEquals(servers, ["cloud-lsp", "container-lsp", "database-lsp"]);
});

Deno.test("buildPlan — fails on cycle", () => {
  const stack = parseString(CYCLE_STACK);
  assert(stack.ok);
  const r = buildPlan(stack.value);
  assert(!r.ok);
  assert(r.error.includes("Cyclic"));
});

Deno.test("buildRollbackPlan — reverses phase order + negates phase numbers", () => {
  const stack = parseString(LINEAR_STACK);
  assert(stack.ok);
  const plan = buildPlan(stack.value);
  assert(plan.ok);
  const rollback = buildRollbackPlan(plan.value);
  assertEquals(rollback.phases.length, 1);
  assertEquals(rollback.phases[0].phase, -1);
  // Component reverse order: c, b, a.
  assertEquals(
    rollback.phases[0].components.map((c) => c.id),
    ["c", "b", "a"],
  );
});

Deno.test("estimateDuration — applies per-type heuristics", () => {
  const stack = parseString(LINEAR_STACK);
  assert(stack.ok);
  const plan = buildPlan(stack.value);
  assert(plan.ok);
  const est = estimateDuration(plan.value);
  // 180k cloud + 360k db + 120k container = 660_000 ms
  assertEquals(est.total_ms, 660_000);
  assert(est.parallel_factor >= 1);
});
