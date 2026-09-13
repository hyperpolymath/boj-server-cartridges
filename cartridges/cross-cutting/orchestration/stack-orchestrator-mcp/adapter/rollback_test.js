// SPDX-License-Identifier: MPL-2.0
import { test } from "bun:test";
import { ok as assert, deepStrictEqual as assertEquals } from "node:assert/strict";
import { executeAllPhases } from "./executor.js";
import { rollback } from "./rollback.js";
import { MockLspClient } from "./lsp_client.js";
import { buildPlan } from "./planner.js";
import { parseString } from "./parser.js";
const SAMPLE_STACK = `
[metadata]
name = "test-stack"
version = "1.0.0"

[[components]]
id = "db"
type = "database.postgresql"
lsp_server = "database-lsp"
phase = 1

[[components]]
id = "monitoring"
type = "observability.prometheus"
lsp_server = "observe-lsp"
phase = 1

[[components]]
id = "app"
type = "container.docker"
lsp_server = "container-lsp"
depends_on = ["db", "monitoring"]
phase = 2

[rollback]
enabled = true
strategy = "cascade"
`;
async function makePlan() {
  const stack = parseString(SAMPLE_STACK);
  assert(stack.ok);
  const plan = buildPlan(stack.value);
  assert(plan.ok);
  return plan.value;
}
test("rollback reverses forward execution in reverse phase order", async () => {
  const plan = await makePlan(), client = new MockLspClient;
  client.setResponse("db", { ok: !0, outputs: {} });
  client.setResponse("monitoring", { ok: !0, outputs: {} });
  client.setResponse("app", { ok: !0, outputs: {} });
  const fwd = await executeAllPhases(plan, { client });
  assert(fwd.ok);
  const executedSteps = fwd.ok ? fwd.value.flatMap((p) => p.steps) : [], callsBeforeRollback = client.calls.length, r = await rollback(plan, { client, executedSteps });
  assert(r.ok);
  if (r.ok) {
    assertEquals(r.value.errors, []);
    const rollbackCalls = client.calls.slice(callsBeforeRollback), appIdx = rollbackCalls.findIndex((c) => c.method === "rollback" && c.id === "app"), dbIdx = rollbackCalls.findIndex((c) => c.method === "rollback" && c.id === "db");
    assert(appIdx >= 0 && dbIdx >= 0);
    assert(appIdx < dbIdx, "app should be rolled back before db");
  }
});
test("rollback respects toPhase to halt mid-rollback", async () => {
  const plan = await makePlan(), client = new MockLspClient;
  client.setResponse("db", { ok: !0, outputs: {} });
  client.setResponse("monitoring", { ok: !0, outputs: {} });
  client.setResponse("app", { ok: !0, outputs: {} });
  const fwd = await executeAllPhases(plan, { client });
  assert(fwd.ok);
  const executedSteps = fwd.ok ? fwd.value.flatMap((p) => p.steps) : [], r = await rollback(plan, { client, executedSteps, toPhase: 2 });
  assert(r.ok);
  if (r.ok) {
    assertEquals(r.value.rolledBack, ["app"]);
    assertEquals(r.value.phasesReverted, [2]);
  }
});
test("rollback skips steps that did not succeed", async () => {
  const plan = await makePlan(), client = new MockLspClient;
  client.setResponse("db", { ok: !1, error: "boom" });
  client.setResponse("monitoring", { ok: !0, outputs: {} });
  const fwd = await executeAllPhases(plan, { client });
  assert(fwd.ok);
  const executedSteps = fwd.ok ? fwd.value.flatMap((p) => p.steps) : [], r = await rollback(plan, { client, executedSteps });
  assert(r.ok);
  if (r.ok) {
    assert(r.value.rolledBack.includes("monitoring"));
    assert(!r.value.rolledBack.includes("db"));
  }
});
test("rollback errors when strategy disabled", async () => {
  const plan = await makePlan(), disabled = { ...plan, rollback_strategy: { ...plan.rollback_strategy, enabled: !1 } }, r = await rollback(disabled, { client: new MockLspClient });
  assertEquals(r.ok, !1);
});
