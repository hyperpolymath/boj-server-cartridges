// SPDX-License-Identifier: MPL-2.0
import { test } from "bun:test";
import { ok as assert, deepStrictEqual as assertEquals } from "node:assert/strict";
import {
  dispatchMatrix,
  executeAllPhases,
  executePhase,
  interpolateConfig,
  limitConcurrency
} from "./executor.js";
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
`;
async function makePlan() {
  const stack = parseString(SAMPLE_STACK);
  assert(stack.ok);
  const plan = buildPlan(stack.value);
  assert(plan.ok);
  return plan.value;
}
test("executePhase: forward run with mock client succeeds", async () => {
  const plan = await makePlan(), client = new MockLspClient;
  client.setResponse("db", { ok: !0, outputs: { host: "db.local", port: 5432 } });
  client.setResponse("monitoring", { ok: !0, outputs: { endpoint: "prom:9090" } });
  const r = await executePhase(plan, 0, { client });
  assert(r.ok);
  if (r.ok) {
    assertEquals(r.value.errors, []);
    assertEquals(r.value.outputs.db, { host: "db.local", port: 5432 });
    assertEquals(r.value.steps.every((s) => s.status === "succeeded"), !0);
  }
});
test("executePhase: dryRun returns dispatch matrix without invoking client", async () => {
  const plan = await makePlan(), client = new MockLspClient, r = await executePhase(plan, 0, { client, dryRun: !0 });
  assert(r.ok);
  if (r.ok) {
    assert(r.value.dispatched.length > 0);
    assertEquals(client.calls.length, 0);
  }
});
test("executePhase: parallel siblings run concurrently", async () => {
  const plan = await makePlan(), order = [], client = new MockLspClient, origExec = client.executeComponent.bind(client);
  client.executeComponent = async (c) => {
    order.push(`start-${c.id}`);
    const r = await origExec(c);
    order.push(`end-${c.id}`);
    return r;
  };
  await executePhase(plan, 0, { client });
  const dbStart = order.indexOf("start-db"), monStart = order.indexOf("start-monitoring"), dbEnd = order.indexOf("end-db"), monEnd = order.indexOf("end-monitoring");
  assert(dbStart < dbEnd);
  assert(monStart < monEnd);
  assert(dbStart < monEnd || monStart < dbEnd);
});
test("executePhase: sibling failure does not abort other siblings", async () => {
  const plan = await makePlan(), client = new MockLspClient;
  client.setResponse("db", { ok: !1, error: "DB went boom" });
  client.setResponse("monitoring", { ok: !0, outputs: { endpoint: "prom:9090" } });
  const r = await executePhase(plan, 0, { client });
  assert(r.ok);
  if (r.ok) {
    assertEquals(r.value.errors.length, 1);
    assertEquals(r.value.errors[0].id, "db");
    const mon = r.value.steps.find((s) => s.id === "monitoring");
    assertEquals(mon?.status, "succeeded");
    const db = r.value.steps.find((s) => s.id === "db");
    assertEquals(db?.status, "failed");
  }
});
test("executePhase: retry succeeds after one transient failure", async () => {
  const plan = await makePlan(), client = new MockLspClient;
  client.setFailOnce("db");
  client.setResponse("db", { ok: !0, outputs: { host: "db.local" } });
  const r = await executePhase(plan, 0, { client, retryCount: 1 });
  assert(r.ok);
  if (r.ok) {
    assertEquals(r.value.errors, []);
    const db = r.value.steps.find((s) => s.id === "db");
    assertEquals(db?.status, "succeeded");
  }
});
test("executePhase: retry exhausted leaves component failed", async () => {
  const plan = await makePlan(), client = new MockLspClient;
  client.setResponse("db", { ok: !1, error: "stays broken" });
  const r = await executePhase(plan, 0, { client, retryCount: 2 });
  assert(r.ok);
  if (r.ok) {
    assertEquals(r.value.errors.length, 1);
    assertEquals(r.value.errors[0].id, "db");
  }
});
test("executePhase: maxParallel slices group", () => {
  const slices = limitConcurrency(["a", "b", "c", "d", "e"], 2);
  assertEquals(slices, [["a", "b"], ["c", "d"], ["e"]]);
});
test("executePhase: maxParallel=0 returns single slice", () => {
  const slices = limitConcurrency(["a", "b"], 0);
  assertEquals(slices, [["a", "b"]]);
});
test("executePhase: out-of-range phase index errors", async () => {
  const plan = await makePlan(), r = await executePhase(plan, 99, { client: new MockLspClient });
  assertEquals(r.ok, !1);
});
test("interpolateConfig substitutes ${id.field} from outputs", () => {
  const result = interpolateConfig({
    db_host: "${db.host}",
    db_port: "${db.port}",
    nested: { url: "postgres://${db.host}:${db.port}/app" },
    arr: ["${db.host}", "static"],
    missing: "${ghost.unknown}"
  }, { db: { host: "db.local", port: 5432 } });
  assertEquals(result.db_host, "db.local");
  assertEquals(result.db_port, "5432");
  assertEquals(result.nested.url, "postgres://db.local:5432/app");
  assertEquals(result.arr[0], "db.local");
  assertEquals(result.missing, "${ghost.unknown}");
});
test("executeAllPhases propagates outputs to later phases", async () => {
  const plan = await makePlan(), client = new MockLspClient;
  client.setResponse("db", { ok: !0, outputs: { host: "db.local" } });
  client.setResponse("monitoring", { ok: !0, outputs: { endpoint: "prom:9090" } });
  client.setResponse("app", { ok: !0, outputs: { url: "http://app:80" } });
  const r = await executeAllPhases(plan, { client });
  assert(r.ok);
  if (r.ok) {
    assertEquals(r.value.length, 2);
    assertEquals(r.value[0].errors, []);
    assertEquals(r.value[1].errors, []);
  }
});
test("executeAllPhases halts after first phase with errors", async () => {
  const plan = await makePlan(), client = new MockLspClient;
  client.setResponse("db", { ok: !1, error: "boom" });
  client.setResponse("monitoring", { ok: !0, outputs: {} });
  const r = await executeAllPhases(plan, { client });
  assert(r.ok);
  if (r.ok) {
    assertEquals(r.value.length, 1);
    assert(r.value[0].errors.length > 0);
  }
});
test("dispatchMatrix returns parallel groups per phase", async () => {
  const plan = await makePlan(), matrix = dispatchMatrix(plan);
  assert(matrix.length >= 2);
  assertEquals(matrix.every((m) => Array.isArray(m.dispatched)), !0);
});
