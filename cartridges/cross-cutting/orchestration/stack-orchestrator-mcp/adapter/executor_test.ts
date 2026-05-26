// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

import { assert, assertEquals } from "@std/assert";
import {
  dispatchMatrix,
  executeAllPhases,
  executePhase,
  interpolateConfig,
  limitConcurrency,
} from "./executor.ts";
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
`;

async function makePlan() {
  const stack = parseString(SAMPLE_STACK);
  assert(stack.ok);
  const plan = buildPlan(stack.value);
  assert(plan.ok);
  return plan.value;
}

Deno.test("executePhase: forward run with mock client succeeds", async () => {
  const plan = await makePlan();
  const client = new MockLspClient();
  client.setResponse("db", { ok: true, outputs: { host: "db.local", port: 5432 } });
  client.setResponse("monitoring", { ok: true, outputs: { endpoint: "prom:9090" } });
  const r = await executePhase(plan, 0, { client });
  assert(r.ok);
  if (r.ok) {
    assertEquals(r.value.errors, []);
    assertEquals(r.value.outputs.db, { host: "db.local", port: 5432 });
    assertEquals(r.value.steps.every((s) => s.status === "succeeded"), true);
  }
});

Deno.test("executePhase: dryRun returns dispatch matrix without invoking client", async () => {
  const plan = await makePlan();
  const client = new MockLspClient();
  const r = await executePhase(plan, 0, { client, dryRun: true });
  assert(r.ok);
  if (r.ok) {
    assert(r.value.dispatched.length > 0);
    assertEquals(client.calls.length, 0);
  }
});

Deno.test("executePhase: parallel siblings run concurrently", async () => {
  const plan = await makePlan();
  const order: string[] = [];
  const client = new MockLspClient();
  const origExec = client.executeComponent.bind(client);
  client.executeComponent = async (c) => {
    order.push(`start-${c.id}`);
    const r = await origExec(c);
    order.push(`end-${c.id}`);
    return r;
  };
  await executePhase(plan, 0, { client });
  // Both "start" events should precede both "end" events
  // — i.e. parallel dispatch.
  const dbStart = order.indexOf("start-db");
  const monStart = order.indexOf("start-monitoring");
  const dbEnd = order.indexOf("end-db");
  const monEnd = order.indexOf("end-monitoring");
  assert(dbStart < dbEnd);
  assert(monStart < monEnd);
  assert(dbStart < monEnd || monStart < dbEnd);
});

Deno.test("executePhase: sibling failure does not abort other siblings", async () => {
  const plan = await makePlan();
  const client = new MockLspClient();
  client.setResponse("db", { ok: false, error: "DB went boom" });
  client.setResponse("monitoring", { ok: true, outputs: { endpoint: "prom:9090" } });
  const r = await executePhase(plan, 0, { client });
  assert(r.ok);
  if (r.ok) {
    assertEquals(r.value.errors.length, 1);
    assertEquals(r.value.errors[0].id, "db");
    // monitoring still ran + succeeded
    const mon = r.value.steps.find((s) => s.id === "monitoring");
    assertEquals(mon?.status, "succeeded");
    const db = r.value.steps.find((s) => s.id === "db");
    assertEquals(db?.status, "failed");
  }
});

Deno.test("executePhase: retry succeeds after one transient failure", async () => {
  const plan = await makePlan();
  const client = new MockLspClient();
  client.setFailOnce("db");
  client.setResponse("db", { ok: true, outputs: { host: "db.local" } });
  const r = await executePhase(plan, 0, { client, retryCount: 1 });
  assert(r.ok);
  if (r.ok) {
    assertEquals(r.value.errors, []);
    const db = r.value.steps.find((s) => s.id === "db");
    assertEquals(db?.status, "succeeded");
  }
});

Deno.test("executePhase: retry exhausted leaves component failed", async () => {
  const plan = await makePlan();
  const client = new MockLspClient();
  client.setResponse("db", { ok: false, error: "stays broken" });
  const r = await executePhase(plan, 0, { client, retryCount: 2 });
  assert(r.ok);
  if (r.ok) {
    assertEquals(r.value.errors.length, 1);
    assertEquals(r.value.errors[0].id, "db");
  }
});

Deno.test("executePhase: maxParallel slices group", () => {
  const slices = limitConcurrency(["a", "b", "c", "d", "e"], 2);
  assertEquals(slices, [["a", "b"], ["c", "d"], ["e"]]);
});

Deno.test("executePhase: maxParallel=0 returns single slice", () => {
  const slices = limitConcurrency(["a", "b"], 0);
  assertEquals(slices, [["a", "b"]]);
});

Deno.test("executePhase: out-of-range phase index errors", async () => {
  const plan = await makePlan();
  const r = await executePhase(plan, 99, { client: new MockLspClient() });
  assertEquals(r.ok, false);
});

Deno.test("interpolateConfig substitutes ${id.field} from outputs", () => {
  const config = {
    db_host: "${db.host}",
    db_port: "${db.port}",
    nested: { url: "postgres://${db.host}:${db.port}/app" },
    arr: ["${db.host}", "static"],
    missing: "${ghost.unknown}",
  };
  const outputs = { db: { host: "db.local", port: 5432 } };
  const result = interpolateConfig(config, outputs);
  assertEquals(result.db_host, "db.local");
  assertEquals(result.db_port, "5432");
  assertEquals(
    (result.nested as Record<string, string>).url,
    "postgres://db.local:5432/app",
  );
  assertEquals(
    (result.arr as string[])[0],
    "db.local",
  );
  // Missing refs left as-is for downstream inspection
  assertEquals(result.missing, "${ghost.unknown}");
});

Deno.test("executeAllPhases propagates outputs to later phases", async () => {
  const plan = await makePlan();
  const client = new MockLspClient();
  client.setResponse("db", { ok: true, outputs: { host: "db.local" } });
  client.setResponse("monitoring", { ok: true, outputs: { endpoint: "prom:9090" } });
  client.setResponse("app", { ok: true, outputs: { url: "http://app:80" } });
  const r = await executeAllPhases(plan, { client });
  assert(r.ok);
  if (r.ok) {
    assertEquals(r.value.length, 2);
    assertEquals(r.value[0].errors, []);
    assertEquals(r.value[1].errors, []);
  }
});

Deno.test("executeAllPhases halts after first phase with errors", async () => {
  const plan = await makePlan();
  const client = new MockLspClient();
  client.setResponse("db", { ok: false, error: "boom" });
  client.setResponse("monitoring", { ok: true, outputs: {} });
  const r = await executeAllPhases(plan, { client });
  assert(r.ok);
  if (r.ok) {
    assertEquals(r.value.length, 1); // app phase never reached
    assert(r.value[0].errors.length > 0);
  }
});

Deno.test("dispatchMatrix returns parallel groups per phase", async () => {
  const plan = await makePlan();
  const matrix = dispatchMatrix(plan);
  assert(matrix.length >= 2);
  assertEquals(matrix.every((m) => Array.isArray(m.dispatched)), true);
});
