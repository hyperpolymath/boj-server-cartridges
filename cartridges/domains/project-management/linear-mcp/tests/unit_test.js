// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// linear-mcp unit / property / regression tests.
//
// Taxonomy (proven-tests-and-benches, src/ProvenTests/Taxonomy.idr):
//   UnitTest       — argument validation and dispatch
//   PropertyTest   — invariants that must hold for every input in a range
//   RegressionTest — the two Linear-specific traps below, pinned so they
//                    cannot silently regress
//   ContractTest   — see tests/parity_test.sh (manifest <-> impl <-> FFI)
//
// The transport is stubbed, so these run offline and deterministically —
// no LINEAR_API_KEY and no network required. Live coverage is E2E's job
// (tests/e2e_test.js, which is skipped without a key).
//
// Run: deno test --allow-env tests/unit_test.js

import { assert, assertEquals } from "jsr:@std/assert@1";
import { handleTool } from "../mod.js";

// ---------------------------------------------------------------------------
// Transport stub — captures the outbound request and replays a scripted reply.
// ---------------------------------------------------------------------------

function withFetch(reply, fn) {
  const real = globalThis.fetch;
  const seen = [];
  globalThis.fetch = (url, opts) => {
    seen.push({ url, opts, headers: opts.headers, body: JSON.parse(opts.body) });
    const { status = 200, json = { data: {} }, headers = {} } = reply;
    return Promise.resolve(
      new Response(JSON.stringify(json), {
        status,
        headers: { "content-type": "application/json", ...headers },
      }),
    );
  };
  return (async () => {
    try {
      return { result: await fn(), seen };
    } finally {
      globalThis.fetch = real;
    }
  })();
}

const KEY = "LINEAR_API_KEY";

// ---------------------------------------------------------------------------
// RegressionTest — Linear personal API keys must NOT be sent as "Bearer".
//
// Linear accepts `Authorization: lin_api_...` raw. Prefixing a personal key
// with "Bearer" is a 401. "Bearer" is correct ONLY for OAuth2 access tokens.
// The pre-0.2.0 cartridge declared auth.method "none" and never sent a key at
// all; the obvious "fix" is to reach for Bearer, which fails. Pin both forms.
// ---------------------------------------------------------------------------

Deno.test("regression: personal API key is sent raw, never Bearer-prefixed", async () => {
  Deno.env.set(KEY, "lin_api_personal_abc123");
  const { seen } = await withFetch(
    { json: { data: { viewer: { id: "u1" }, organization: { id: "o1" } } } },
    () => handleTool("linear_whoami", {}),
  );
  assertEquals(seen[0].headers["Authorization"], "lin_api_personal_abc123");
  assert(!seen[0].headers["Authorization"].startsWith("Bearer"));
});

Deno.test("regression: OAuth2 access token IS Bearer-prefixed", async () => {
  Deno.env.set(KEY, "oauth_access_token_xyz");
  const { seen } = await withFetch(
    { json: { data: { viewer: {}, organization: {} } } },
    () => handleTool("linear_whoami", {}),
  );
  assertEquals(seen[0].headers["Authorization"], "Bearer oauth_access_token_xyz");
});

// ---------------------------------------------------------------------------
// RegressionTest — Linear signals rate limiting as HTTP 400 + a GraphQL error
// with extensions.code == "RATELIMITED", NOT HTTP 429.
//
// Code that only checks `status === 429` (as the sibling todoist-mcp cartridge
// does) reads this as a generic bad request and reports a confusing error.
// ---------------------------------------------------------------------------

Deno.test("regression: RATELIMITED at HTTP 400 is normalised to 429", async () => {
  Deno.env.set(KEY, "lin_api_k");
  const { result } = await withFetch(
    {
      status: 400,
      json: { errors: [{ message: "rate limited", extensions: { code: "RATELIMITED" } }] },
      headers: { "x-ratelimit-requests-remaining": "0" },
    },
    () => handleTool("linear_list_issues", {}),
  );
  assertEquals(result.status, 429);
  assertEquals(result.rateLimited, true);
  assertEquals(result.limits["x-ratelimit-requests-remaining"], "0");
});

Deno.test("a plain HTTP 400 is NOT mistaken for a rate limit", async () => {
  Deno.env.set(KEY, "lin_api_k");
  const { result } = await withFetch(
    { status: 400, json: { errors: [{ message: "Field 'nope' doesn't exist" }] } },
    () => handleTool("linear_list_issues", {}),
  );
  assertEquals(result.status, 400);
  assertEquals(result.rateLimited, undefined);
  assert(result.error.includes("nope"));
});

// ---------------------------------------------------------------------------
// UnitTest — issue lookup routes by identifier shape.
//
// Linear's issue(id:) resolves UUIDs only. "ENG-123" must go through a
// filtered issues() query on team key + number instead.
// ---------------------------------------------------------------------------

Deno.test("get_issue: human identifier ENG-123 routes to a filtered query", async () => {
  Deno.env.set(KEY, "lin_api_k");
  const { seen } = await withFetch(
    { json: { data: { issues: { nodes: [{ id: "x", identifier: "ENG-123" }] } } } },
    () => handleTool("linear_get_issue", { issue_id: "ENG-123" }),
  );
  const { query, variables } = seen[0].body;
  assert(query.includes("GetIssueByIdentifier"));
  assertEquals(variables.filter.team.key.eqIgnoreCase, "ENG");
  assertEquals(variables.filter.number.eq, 123);
});

Deno.test("get_issue: a UUID routes to issue(id:)", async () => {
  Deno.env.set(KEY, "lin_api_k");
  const { seen } = await withFetch(
    { json: { data: { issue: { id: "uuid-1" } } } },
    () => handleTool("linear_get_issue", { issue_id: "3fa85f64-5717-4562-b3fc-2c963f66afa6" }),
  );
  assert(seen[0].body.query.includes("GetIssue("));
  assert(!seen[0].body.query.includes("GetIssueByIdentifier"));
});

Deno.test("get_issue: a missing issue is 404, not an empty success", async () => {
  Deno.env.set(KEY, "lin_api_k");
  const { result } = await withFetch(
    { json: { data: { issue: null } } },
    () => handleTool("linear_get_issue", { issue_id: "3fa85f64-5717-4562-b3fc-2c963f66afa6" }),
  );
  assertEquals(result.status, 404);
});

// ---------------------------------------------------------------------------
// PropertyTest — priority accepts exactly Linear's 0..4 scale, nothing else.
// ---------------------------------------------------------------------------

Deno.test("property: set_priority accepts 0..4 and rejects everything else", async () => {
  Deno.env.set(KEY, "lin_api_k");

  for (const p of [0, 1, 2, 3, 4]) {
    const { result } = await withFetch(
      { json: { data: { issueUpdate: { success: true, issue: {} } } } },
      () => handleTool("linear_set_priority", { issue_id: "i", priority: p }),
    );
    assertEquals(result.status, 200, `priority ${p} should be accepted`);
  }

  for (const p of [-1, 5, 99, 1.5]) {
    const r = await handleTool("linear_set_priority", { issue_id: "i", priority: p });
    assertEquals(r.status, 400, `priority ${p} should be rejected`);
  }
});

// ---------------------------------------------------------------------------
// UnitTest — the auth guard fires before any network call is attempted.
// ---------------------------------------------------------------------------

Deno.test("no API key: refuses with 401 and makes no request", async () => {
  Deno.env.delete(KEY);
  const { result, seen } = await withFetch(
    { json: { data: {} } },
    () => handleTool("linear_list_issues", {}),
  );
  assertEquals(result.status, 401);
  assertEquals(seen.length, 0, "must not hit the network without a key");
});

// ---------------------------------------------------------------------------
// UnitTest — required-argument validation short-circuits before the network.
// ---------------------------------------------------------------------------

Deno.test("required arguments are validated before any request", async () => {
  Deno.env.set(KEY, "lin_api_k");
  const cases = [
    ["linear_get_issue", {}],
    ["linear_create_issue", { team_id: "t" }], // no title
    ["linear_create_comment", { issue_id: "i" }], // no body
    ["linear_create_attachment", { issue_id: "i" }], // no url
    ["linear_create_project", { name: "n" }], // no team_ids
    ["linear_search_issues", {}], // no query
  ];
  for (const [tool, args] of cases) {
    const { result, seen } = await withFetch({ json: { data: {} } }, () => handleTool(tool, args));
    assertEquals(result.status, 400, `${tool} should reject`);
    assertEquals(seen.length, 0, `${tool} must not hit the network`);
  }
});

Deno.test("unknown tool is a clean 404", async () => {
  Deno.env.set(KEY, "lin_api_k");
  const r = await handleTool("linear_not_a_tool", {});
  assertEquals(r.status, 404);
});

// ---------------------------------------------------------------------------
// PropertyTest — page size is clamped to Linear's ceiling on every list tool.
// ---------------------------------------------------------------------------

Deno.test("property: limit is clamped to 250 and defaults to 50", async () => {
  Deno.env.set(KEY, "lin_api_k");
  const probe = async (limit) => {
    const { seen } = await withFetch(
      { json: { data: { teams: { nodes: [] } } } },
      () => handleTool("linear_list_teams", limit === undefined ? {} : { limit }),
    );
    return seen[0].body.variables.first;
  };
  assertEquals(await probe(undefined), 50);
  assertEquals(await probe(10), 10);
  assertEquals(await probe(10_000), 250);
});
