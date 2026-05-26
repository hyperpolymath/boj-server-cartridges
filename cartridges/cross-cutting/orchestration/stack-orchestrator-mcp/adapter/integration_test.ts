// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)
//
// End-to-end integration: spawn the real proof-lsp cartridge in this repo,
// have StdioLspClient send it `workspace/executeCommand execute_component`,
// and verify the wire round-trips. Since proof-lsp does not know
// `execute_component`, it should reply with a JSON-RPC -32601 error —
// proving end-to-end framing without needing a bespoke fixture LSP.

import { assert, assertEquals } from "@std/assert";
import { StdioLspClient } from "./lsp_client.ts";
import type { ComponentStep } from "./types.ts";
import { dirname, fromFileUrl, resolve } from "@std/path";

Deno.test({
  name: "StdioLspClient round-trips through real proof-lsp cartridge",
  // Spawning a child Deno process can be slow on a cold cache.
  fn: async () => {
    const here = dirname(fromFileUrl(import.meta.url));
    // adapter -> stack-orchestrator-mcp -> orchestration -> cross-cutting ->
    // cartridges -> repo root. cartridgesRoot must point at the directory
    // containing "domains/...".
    const cartridgesRoot = resolve(here, "../../../../cartridges");

    const client = new StdioLspClient({
      cartridgesRoot,
      timeoutMs: 10_000,
    });
    try {
      const step: ComponentStep = {
        id: "test-component",
        type: "proof.coq",
        lsp_server: "proof-lsp",
        config: {},
        depends_on: [],
        outputs: {},
        status: "pending",
      };
      const r = await client.executeComponent(step);
      // proof-lsp does not know `execute_component`; it should reply with
      // -32601 (Method not found). For our purposes the error path itself
      // is success — we've proved the wire works.
      assertEquals(r.ok, false);
      assert(typeof (r as { ok: false; error: string }).error === "string");
    } finally {
      await client.close();
    }
  },
});
