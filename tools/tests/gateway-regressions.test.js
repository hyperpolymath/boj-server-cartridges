// SPDX-License-Identifier: MPL-2.0
import { test, expect } from "bun:test";
import { handleTool as aws } from "../../cartridges/domains/cloud/aws-mcp/mod.js";
import { handleTool as vext } from "../../cartridges/domains/security/vext-mcp/mod.js";
test("Lambda forwards the caller payload without shadowing it", async () => {
  const saved = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async (url, opts) => {
    calls.push({url, body: JSON.parse(opts.body)});
    return Response.json({accepted: true});
  };
  try {
    expect((await aws("aws_lambda_invoke", {function_name: "example", payload: {n:42}})).status).toBe(200);
    expect(calls[0].body).toEqual({function_name:"example", payload:{n:42}});
    expect((await aws("aws_lambda_invoke", {})).status).toBe(400);
    expect(calls.length).toBe(1);
  } finally { globalThis.fetch = saved; }
});
test("Vext chain append forwards the payload once", async () => {
  const saved = globalThis.fetch; let seen;
  globalThis.fetch = async (_, opts) => { seen = JSON.parse(opts.body); return Response.json({accepted:true}); };
  try {
    const result = await vext("vext_append_chain", {payload: "entry"});
    expect(result.status).toBe(200);
    expect(seen).toEqual({payload: "entry"});
  } finally { globalThis.fetch = saved; }
});
