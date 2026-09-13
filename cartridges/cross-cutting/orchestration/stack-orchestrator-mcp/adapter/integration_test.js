// SPDX-License-Identifier: MPL-2.0
import { test } from "bun:test";
import { ok as assert, deepStrictEqual as assertEquals } from "node:assert/strict";
import { StdioLspClient } from "./lsp_client.js";
import { dirname, resolve } from "node:path";
import { fileURLToPath as fromFileUrl } from "node:url";
test("StdioLspClient round-trips through real proof-lsp cartridge", async () => {
  const here = dirname(fromFileUrl(import.meta.url)), cartridgesRoot = resolve(here, "../../../.."), client = new StdioLspClient({
    cartridgesRoot,
    timeoutMs: 1e4
  });
  try {
    const step = {
      id: "test-component",
      type: "proof.coq",
      lsp_server: "proof-lsp",
      config: {},
      depends_on: [],
      outputs: {},
      status: "pending"
    }, r = await client.executeComponent(step);
    assertEquals(r.ok, !1);
    assert(typeof r.error === "string");
  } finally {
    await client.close();
  }
});
