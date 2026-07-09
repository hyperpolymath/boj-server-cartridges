// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// cicd-squabbler-mcp/mod.js — CI/CD gate fighter gateway (squabble != bypass)
//
// Delegates to the squabble-app loopback backend at http://127.0.0.1:7741
// (override with SQUABBLE_BACKEND_URL). The backend is the same shared
// planner the `squabble` CLI uses; this gateway only proxies — the cartridge
// sandbox has no subprocess capability, and the squabbler's gate invariant
// (green only by satisfying required checks, never by weakening them) lives
// in squabble-core, not here.

const BASE_URL = Deno.env.get("SQUABBLE_BACKEND_URL") ?? "http://127.0.0.1:7741";
const TIMEOUT_MS = 15_000;

async function post(path, payload) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  try {
    const r = await fetch(`${BASE_URL}${path}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
      signal: ctrl.signal,
    });
    const data = await r.json().catch(() => ({ success: false, error: "non-JSON response" }));
    return { status: r.status, data };
  } catch (e) {
    if (e.name === "AbortError") return { status: 504, data: { success: false, error: "cicd-squabbler-mcp backend timed out" } };
    return { status: 503, data: { success: false, error: `cicd-squabbler-mcp backend unavailable: ${e.message}` } };
  } finally { clearTimeout(t); }
}

export async function handleTool(toolName, args) {
  switch (toolName) {
    case "squabble_fight": {
      const { slug, gate } = args ?? {};
      if (!slug || !gate) {
        return { status: 400, data: { error: "slug and gate are required" } };
      }
      // Pass through exactly what the backend's FightRequest expects.
      const payload = { slug, gate };
      if (args.repo_root) payload.repo_root = args.repo_root;
      return post("/api/v1/fight", payload);
    }
    case "squabble_diagnose": {
      const { checks } = args ?? {};
      if (!Array.isArray(checks)) {
        return { status: 400, data: { error: "checks (array) is required" } };
      }
      // The backend takes the Gate object directly.
      return post("/api/v1/diagnose", { checks });
    }
    default:
      return { status: 404, data: { error: `Unknown tool: ${toolName}` } };
  }
}
