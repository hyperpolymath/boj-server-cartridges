// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

import { assert, assertEquals } from "@std/assert";
import { executeAllPhases } from "./executor.ts";
import { rollback } from "./rollback.ts";
import { MockLspClient } from "./lsp_client.ts";
import { buildPlan } from "./planner.ts";
import { parseString } from "./parser.ts";

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

Deno.test("rollback reverses forward execution in reverse phase order", async () => {
  const plan = await makePlan();
  const client = new MockLspClient();
  client.setResponse("db", { ok: true, outputs: {} });
  client.setResponse("monitoring", { ok: true, outputs: {} });
  client.setResponse("app", { ok: true, outputs: {} });

  const fwd = await executeAllPhases(plan, { client });
  assert(fwd.ok);
  const executedSteps = fwd.ok ? fwd.value.flatMap((p) => p.steps) : [];

  const callsBeforeRollback = client.calls.length;
  const r = await rollback(plan, { client, executedSteps });
  assert(r.ok);
  if (r.ok) {
    assertEquals(r.value.errors, []);
    // app rolled back first (phase 2), then db + monitoring (phase 1)
    const rollbackCalls = client.calls.slice(callsBeforeRollback);
    const appIdx = rollbackCalls.findIndex(
      (c) => c.method === "rollback" && c.id === "app",
    );
    const dbIdx = rollbackCalls.findIndex(
      (c) => c.method === "rollback" && c.id === "db",
    );
    assert(appIdx >= 0 && dbIdx >= 0);
    assert(appIdx < dbIdx, "app should be rolled back before db");
  }
});

Deno.test("rollback respects toPhase to halt mid-rollback", async () => {
  const plan = await makePlan();
  const client = new MockLspClient();
  client.setResponse("db", { ok: true, outputs: {} });
  client.setResponse("monitoring", { ok: true, outputs: {} });
  client.setResponse("app", { ok: true, outputs: {} });
  const fwd = await executeAllPhases(plan, { client });
  assert(fwd.ok);
  const executedSteps = fwd.ok ? fwd.value.flatMap((p) => p.steps) : [];

  const r = await rollback(plan, { client, executedSteps, toPhase: 2 });
  assert(r.ok);
  if (r.ok) {
    // Only phase 2 (app) reverted; phase 1 components untouched.
    assertEquals(r.value.rolledBack, ["app"]);
    assertEquals(r.value.phasesReverted, [2]);
  }
});

Deno.test("rollback skips steps that did not succeed", async () => {
  const plan = await makePlan();
  const client = new MockLspClient();
  client.setResponse("db", { ok: false, error: "boom" });
  client.setResponse("monitoring", { ok: true, outputs: {} });
  const fwd = await executeAllPhases(plan, { client });
  assert(fwd.ok);
  const executedSteps = fwd.ok ? fwd.value.flatMap((p) => p.steps) : [];

  // db failed → should not be rolled back; monitoring succeeded → should.
  const r = await rollback(plan, { client, executedSteps });
  assert(r.ok);
  if (r.ok) {
    assert(r.value.rolledBack.includes("monitoring"));
    assert(!r.value.rolledBack.includes("db"));
  }
});

Deno.test("rollback errors when strategy disabled", async () => {
  const plan = await makePlan();
  const disabled = { ...plan, rollback_strategy: { ...plan.rollback_strategy, enabled: false } };
  const r = await rollback(disabled, { client: new MockLspClient() });
  assertEquals(r.ok, false);
});
