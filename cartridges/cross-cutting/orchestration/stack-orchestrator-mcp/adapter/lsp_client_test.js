// SPDX-License-Identifier: MPL-2.0
import { test } from "bun:test";
import { ok as assert, deepStrictEqual as assertEquals } from "node:assert/strict";
import { lspServerToPath, MockLspClient } from "./lsp_client.js";
function step(id, lsp_server = "proof-lsp") {
  return {
    id,
    type: "proof.coq",
    lsp_server,
    config: {},
    depends_on: [],
    outputs: {},
    status: "pending"
  };
}
test("MockLspClient: default response shape", async () => {
  const r = await new MockLspClient().executeComponent(step("alpha"));
  assert(r.ok);
  assertEquals(r.value, {
    default: "output-of-alpha"
  });
});
test("MockLspClient: setResponse overrides default", async () => {
  const c = new MockLspClient;
  c.setResponse("alpha", { ok: !0, outputs: { ip: "10.0.0.1" } });
  const r = await c.executeComponent(step("alpha"));
  assert(r.ok);
  assertEquals(r.value, { ip: "10.0.0.1" });
});
test("MockLspClient: error response", async () => {
  const c = new MockLspClient;
  c.setResponse("bad", { ok: !1, error: "kaboom" });
  const r = await c.executeComponent(step("bad"));
  assertEquals(r.ok, !1);
});
test("MockLspClient: setFailOnce yields one failure then success", async () => {
  const c = new MockLspClient;
  c.setFailOnce("flaky");
  c.setResponse("flaky", { ok: !0, outputs: { ok: 1 } });
  const r1 = await c.executeComponent(step("flaky"));
  assertEquals(r1.ok, !1);
  const r2 = await c.executeComponent(step("flaky"));
  assertEquals(r2.ok, !0);
});
test("MockLspClient: records calls in order", async () => {
  const c = new MockLspClient;
  await c.executeComponent(step("a"));
  await c.rollbackComponent(step("b"));
  await c.executeComponent(step("c"));
  assertEquals(c.calls, [
    { method: "execute", id: "a" },
    { method: "rollback", id: "b" },
    { method: "execute", id: "c" }
  ]);
});
test("lspServerToPath: direct mapping for proof-lsp", () => {
  assertEquals(lspServerToPath("proof-lsp"), "domains/formal-verification/proof-lsp");
});
test("lspServerToPath: legacy poly-proof -> proof-lsp path", () => {
  assertEquals(lspServerToPath("poly-proof"), "domains/formal-verification/proof-lsp");
});
test("lspServerToPath: cloud-lsp", () => {
  assertEquals(lspServerToPath("cloud-lsp"), "domains/cloud/cloud-lsp");
});
test("lspServerToPath: k8s-lsp", () => {
  assertEquals(lspServerToPath("k8s-lsp"), "domains/container/k8s-lsp");
});
test("lspServerToPath: unknown server returns as-is", () => {
  assertEquals(lspServerToPath("unknown-thing"), "unknown-thing");
});

for (const [label, script] of [
  ["malformed JSON", 'process.stdin.once("data", () => process.stdout.write("Content-Length: 1\\r\\n\\r\\n{"));'],
  ["silent backend", 'process.stdin.resume(); setInterval(() => {}, 1000);']
]) {
  test(`StdioLspClient bounds ${label} and returns an unknown outcome`, async () => {
    const {mkdtemp, mkdir, writeFile, rm} = await import("node:fs/promises");
    const {tmpdir} = await import("node:os");
    const {join} = await import("node:path");
    const {StdioLspClient} = await import("./lsp_client.js");
    const root = await mkdtemp(join(tmpdir(), "boj-lsp-control-"));
    await mkdir(join(root, "control-mcp/adapter"), {recursive: true});
    await writeFile(join(root, "control-mcp/adapter/server.js"), script);
    const client = new StdioLspClient({cartridgesRoot: root, timeoutMs: 100});
    const started = Date.now();
    try {
      const result = await client.executeComponent(step("control", "control-mcp"));
      assertEquals(result.ok, false);
      assert(/outcome unknown/.test(result.error));
      assert(Date.now() - started < 2000);
      if (label === "malformed JSON") assert(/JSON/.test(result.error));
    } finally { await client.close(); await rm(root, {recursive: true}); }
  });
}
