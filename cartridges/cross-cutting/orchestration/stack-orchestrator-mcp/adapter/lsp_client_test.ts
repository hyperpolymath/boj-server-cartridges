// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

import { assert, assertEquals } from "@std/assert";
import { lspServerToPath, MockLspClient } from "./lsp_client.ts";
import type { ComponentStep } from "./types.ts";

function step(id: string, lsp_server = "proof-lsp"): ComponentStep {
  return {
    id,
    type: "proof.coq",
    lsp_server,
    config: {},
    depends_on: [],
    outputs: {},
    status: "pending",
  };
}

Deno.test("MockLspClient: default response shape", async () => {
  const c = new MockLspClient();
  const r = await c.executeComponent(step("alpha"));
  assert(r.ok);
  assertEquals((r as { ok: true; value: Record<string, unknown> }).value, {
    default: "output-of-alpha",
  });
});

Deno.test("MockLspClient: setResponse overrides default", async () => {
  const c = new MockLspClient();
  c.setResponse("alpha", { ok: true, outputs: { ip: "10.0.0.1" } });
  const r = await c.executeComponent(step("alpha"));
  assert(r.ok);
  assertEquals(
    (r as { ok: true; value: Record<string, unknown> }).value,
    { ip: "10.0.0.1" },
  );
});

Deno.test("MockLspClient: error response", async () => {
  const c = new MockLspClient();
  c.setResponse("bad", { ok: false, error: "kaboom" });
  const r = await c.executeComponent(step("bad"));
  assertEquals(r.ok, false);
});

Deno.test("MockLspClient: setFailOnce yields one failure then success", async () => {
  const c = new MockLspClient();
  c.setFailOnce("flaky");
  c.setResponse("flaky", { ok: true, outputs: { ok: 1 } });
  const r1 = await c.executeComponent(step("flaky"));
  assertEquals(r1.ok, false);
  const r2 = await c.executeComponent(step("flaky"));
  assertEquals(r2.ok, true);
});

Deno.test("MockLspClient: records calls in order", async () => {
  const c = new MockLspClient();
  await c.executeComponent(step("a"));
  await c.rollbackComponent(step("b"));
  await c.executeComponent(step("c"));
  assertEquals(c.calls, [
    { method: "execute", id: "a" },
    { method: "rollback", id: "b" },
    { method: "execute", id: "c" },
  ]);
});

Deno.test("lspServerToPath: direct mapping for proof-lsp", () => {
  assertEquals(
    lspServerToPath("proof-lsp"),
    "domains/formal-verification/proof-lsp",
  );
});

Deno.test("lspServerToPath: legacy poly-proof -> proof-lsp path", () => {
  assertEquals(
    lspServerToPath("poly-proof"),
    "domains/formal-verification/proof-lsp",
  );
});

Deno.test("lspServerToPath: cloud-lsp", () => {
  assertEquals(lspServerToPath("cloud-lsp"), "domains/cloud/cloud-lsp");
});

Deno.test("lspServerToPath: k8s-lsp", () => {
  assertEquals(lspServerToPath("k8s-lsp"), "domains/container/k8s-lsp");
});

Deno.test("lspServerToPath: unknown server returns as-is", () => {
  assertEquals(lspServerToPath("unknown-thing"), "unknown-thing");
});
