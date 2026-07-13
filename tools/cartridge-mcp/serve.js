// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// cartridge-mcp — serve ANY cartridge directly as an MCP server over stdio.
//
// Why this exists
// ---------------
// A cartridge already contains everything an MCP server needs:
//
//   cartridge.json  ->  tool names + JSON Schemas  (the MCP tools/list response)
//   mod.js          ->  handleTool(name, args)     (the MCP tools/call handler)
//
// but there was no way to actually reach it. The published boj-server is an
// MCP->REST proxy: it expects a BoJ REST API at BOJ_URL (default
// http://localhost:7700), carries a hardcoded list of 23 cartridge names, and
// never fetches this repo — so 119 of the 142 cartridges here are unreachable,
// and even the reachable ones go through a generic boj_cartridge_invoke
// dispatcher that hands the model no per-tool schema.
//
// This shim closes that gap with no backend and no dependencies: every tool in
// cartridge.json becomes a first-class MCP tool, with its own schema, so a
// small model can drive it.
//
// Usage
// -----
//   deno run --allow-net --allow-env --allow-read \
//     tools/cartridge-mcp/serve.js cartridges/domains/project-management/linear-mcp
//
// Register with Claude Code:
//   claude mcp add linear -- deno run --allow-net --allow-env --allow-read \
//     <abs>/tools/cartridge-mcp/serve.js <abs>/cartridges/domains/project-management/linear-mcp
//
// Protocol: JSON-RPC 2.0 over stdio, MCP 2024-11-05. Hand-rolled rather than
// pulling the TypeScript SDK — the repo's language policy keeps node_modules out
// of production, and the surface we need is three methods.

const PROTOCOL_VERSION = "2024-11-05";

// ---------------------------------------------------------------------------
// Load the cartridge
// ---------------------------------------------------------------------------

const dir = Deno.args[0];
if (!dir) {
  console.error("usage: serve.js <cartridge-dir>");
  Deno.exit(2);
}

const cartDir = await Deno.realPath(dir).catch(() => {
  console.error(`cartridge-mcp: no such directory: ${dir}`);
  Deno.exit(2);
});

let manifest;
try {
  manifest = JSON.parse(await Deno.readTextFile(`${cartDir}/cartridge.json`));
} catch (e) {
  console.error(`cartridge-mcp: cannot read ${cartDir}/cartridge.json — ${e.message}`);
  Deno.exit(2);
}

let handleTool;
try {
  ({ handleTool } = await import(`file://${cartDir}/mod.js`));
} catch (e) {
  console.error(`cartridge-mcp: cannot import ${cartDir}/mod.js — ${e.message}`);
  Deno.exit(2);
}

if (typeof handleTool !== "function") {
  console.error(`cartridge-mcp: ${cartDir}/mod.js does not export handleTool()`);
  Deno.exit(2);
}

const TOOLS = (manifest.tools ?? []).map((t) => ({
  name: t.name,
  description: t.description,
  inputSchema: t.inputSchema ?? { type: "object", properties: {} },
}));

// Diagnostics go to stderr — stdout is the JSON-RPC channel and must stay clean.
console.error(
  `cartridge-mcp: ${manifest.name}@${manifest.version} — ${TOOLS.length} tools ` +
    `(auth: ${manifest.auth?.method ?? "none"}${
      manifest.auth?.env_var ? `, env ${manifest.auth.env_var}` : ""
    })`,
);

if (manifest.auth?.env_var && !Deno.env.get(manifest.auth.env_var)) {
  console.error(
    `cartridge-mcp: WARNING ${manifest.auth.env_var} is not set — ` +
      `tools requiring auth will return 401.`,
  );
}

// ---------------------------------------------------------------------------
// JSON-RPC plumbing
// ---------------------------------------------------------------------------

const enc = new TextEncoder();

function send(msg) {
  Deno.stdout.writeSync(enc.encode(JSON.stringify(msg) + "\n"));
}

const reply = (id, result) => send({ jsonrpc: "2.0", id, result });
const fail = (id, code, message) => send({ jsonrpc: "2.0", id, error: { code, message } });

async function dispatch(msg) {
  const { id, method, params } = msg;

  switch (method) {
    case "initialize":
      return reply(id, {
        protocolVersion: PROTOCOL_VERSION,
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: manifest.name, version: manifest.version },
      });

    // Notifications carry no id and must never be answered.
    case "notifications/initialized":
      return;

    case "ping":
      return reply(id, {});

    case "tools/list":
      return reply(id, { tools: TOOLS });

    case "tools/call": {
      const name = params?.name;
      const args = params?.arguments ?? {};

      if (!TOOLS.some((t) => t.name === name)) {
        return fail(id, -32602, `Unknown tool: ${name}`);
      }

      let out;
      try {
        out = await handleTool(name, args);
      } catch (e) {
        // A cartridge throwing must not take the server down.
        return reply(id, {
          content: [{ type: "text", text: `${name} threw: ${e.message}` }],
          isError: true,
        });
      }

      // Cartridges answer {status, data} | {status, error}. Map a non-2xx status
      // onto isError so the model is told plainly that the call failed, rather
      // than being handed an error body that looks like a result.
      const failed = typeof out?.status === "number" && out.status >= 400;
      const payload = failed ? (out.error ?? out) : (out.data ?? out);

      return reply(id, {
        content: [{
          type: "text",
          text: typeof payload === "string" ? payload : JSON.stringify(payload, null, 2),
        }],
        isError: failed,
      });
    }

    default:
      if (id !== undefined) fail(id, -32601, `Method not found: ${method}`);
  }
}

// ---------------------------------------------------------------------------
// stdio read loop — newline-delimited JSON, tolerant of partial reads.
// ---------------------------------------------------------------------------

let buf = "";
const dec = new TextDecoder();

for await (const chunk of Deno.stdin.readable) {
  buf += dec.decode(chunk, { stream: true });

  let nl;
  while ((nl = buf.indexOf("\n")) !== -1) {
    const line = buf.slice(0, nl).trim();
    buf = buf.slice(nl + 1);
    if (!line) continue;

    let msg;
    try {
      msg = JSON.parse(line);
    } catch {
      fail(null, -32700, "Parse error");
      continue;
    }

    try {
      await dispatch(msg);
    } catch (e) {
      if (msg?.id !== undefined) fail(msg.id, -32603, `Internal error: ${e.message}`);
    }
  }
}
