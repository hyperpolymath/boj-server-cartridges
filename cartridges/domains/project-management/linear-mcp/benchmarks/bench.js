// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// linear-mcp benchmarks.
//
// Two tiers, because they answer different questions:
//
//   1. Dispatch (offline, deterministic) — the cost this cartridge ADDS:
//      argument validation, query construction, response shaping. The transport
//      is stubbed, so a regression here is ours and CI can gate on it.
//
//   2. Live transport (opt-in) — end-to-end latency against Linear itself. Only
//      runs with LINEAR_API_KEY set, and is NOT a regression gate: it measures
//      Linear's network, not our code.
//
// Run: deno bench --allow-env --allow-net benchmarks/bench.js

import { handleTool } from "../mod.js";

// ---------------------------------------------------------------------------
// Tier 1 — dispatch overhead with a stubbed transport.
// ---------------------------------------------------------------------------

const CANNED = {
  issues: { nodes: Array.from({ length: 50 }, (_, i) => ({ id: `i${i}`, identifier: `ENG-${i}` })), pageInfo: {} },
  teams: { nodes: Array.from({ length: 50 }, (_, i) => ({ id: `t${i}`, key: `T${i}` })) },
  issueUpdate: { success: true, issue: { id: "i" } },
};

// Captured BEFORE stubbing — the live tier must not replay the stub and
// report a fake sub-millisecond "network" latency.
const REAL_FETCH = globalThis.fetch;

function stubTransport() {
  globalThis.fetch = () =>
    Promise.resolve(
      new Response(JSON.stringify({ data: CANNED }), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );
}

Deno.env.set("LINEAR_API_KEY", "lin_api_bench");
stubTransport();

Deno.bench("dispatch: list_issues (50 nodes, stubbed transport)", async () => {
  await handleTool("linear_list_issues", { team_id: "t", limit: 50 });
});

Deno.bench("dispatch: get_issue by UUID", async () => {
  await handleTool("linear_get_issue", { issue_id: "3fa85f64-5717-4562-b3fc-2c963f66afa6" });
});

Deno.bench("dispatch: get_issue by identifier (ENG-123 -> filter)", async () => {
  await handleTool("linear_get_issue", { issue_id: "ENG-123" });
});

Deno.bench("dispatch: set_priority (validation + mutation)", async () => {
  await handleTool("linear_set_priority", { issue_id: "i", priority: 2 });
});

// The rejection path must stay cheap — it is the one that fires under abuse.
Deno.bench("dispatch: rejected arg (no network)", async () => {
  await handleTool("linear_create_issue", { team_id: "t" });
});

// ---------------------------------------------------------------------------
// Tier 2 — live transport. Opt-in; skipped without a real key.
// ---------------------------------------------------------------------------

const liveKey = Deno.env.get("LINEAR_LIVE_KEY");

Deno.bench({
  name: "live: whoami round-trip to api.linear.app",
  ignore: !liveKey,
  async fn() {
    globalThis.fetch = REAL_FETCH;
    Deno.env.set("LINEAR_API_KEY", liveKey);
    try {
      await handleTool("linear_whoami", {});
    } finally {
      stubTransport();
    }
  },
});
