// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
import { afterEach, expect, test } from "bun:test";
import { handleTool } from "../mod.js";

// These fixtures validate the transport boundary, not a real SSG or deployment.
const tools = ["ssg_load_content", "ssg_build", "ssg_preview", "ssg_deploy", "ssg_clean"];
const originalBackend = process.env.SSG_BACKEND_URL;
let server;

afterEach(() => {
  server?.stop(true);
  server = undefined;
  if (originalBackend === undefined) delete process.env.SSG_BACKEND_URL;
  else process.env.SSG_BACKEND_URL = originalBackend;
});

test("missing or blank backend configuration rejects every tool without networking", async () => {
  const originalFetch = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = async () => {
    calls++;
    throw new Error("unexpected network request");
  };
  try {
    for (const value of [undefined, "", "  "]) {
      if (value === undefined) delete process.env.SSG_BACKEND_URL;
      else process.env.SSG_BACKEND_URL = value;
      for (const tool of tools) {
        const result = await handleTool(tool, {});
        expect(result.status).toBe(503);
        expect(result.data.success).toBe(false);
        expect(result.data.error).toContain("not configured");
      }
    }
    expect(calls).toBe(0);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("explicit configuration forwards each tool over HTTP and preserves the backend result", async () => {
  const requests = [];
  server = Bun.serve({
    hostname: "127.0.0.1",
    port: 0,
    async fetch(request) {
      const path = new URL(request.url).pathname;
      requests.push({ method: request.method, path, args: await request.json() });
      return Response.json({ success: true, fixture: "transport-only", path });
    },
  });
  process.env.SSG_BACKEND_URL = server.url.origin;
  for (const tool of tools) {
    const path = `/api/v1/${tool}`;
    expect(await handleTool(tool, { fixture: tool })).toEqual({
      status: 200,
      data: { success: true, fixture: "transport-only", path },
    });
  }
  expect(requests).toEqual(tools.map(tool => ({
    method: "POST", path: `/api/v1/${tool}`, args: { fixture: tool },
  })));
});

test("an explicit backend failure is not reported as a successful build", async () => {
  server = Bun.serve({
    hostname: "127.0.0.1",
    port: 0,
    fetch: () => Response.json({ success: false, error: "fixture rejected build" }, { status: 503 }),
  });
  process.env.SSG_BACKEND_URL = server.url.origin;
  expect(await handleTool("ssg_build", { session_id: 1 })).toEqual({
    status: 503, data: { success: false, error: "fixture rejected build" },
  });
});

test("an unknown tool stays unknown even when no backend is configured", async () => {
  delete process.env.SSG_BACKEND_URL;
  expect((await handleTool("unknown", {})).status).toBe(404);
});
