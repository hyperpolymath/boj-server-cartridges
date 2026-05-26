// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

import { assert, assertEquals, assertExists } from "@std/assert";
import {
  defaultOpts,
  dispatch,
  encodeFramed,
  FrameDecoder,
} from "./server.ts";
import type { JsonRpcResponse } from "./types.ts";

Deno.test("FrameDecoder decodes a single framed message", () => {
  const payload = { jsonrpc: "2.0" as const, id: 1, method: "initialize", params: {} };
  const framed = encodeFramed(payload);
  const decoder = new FrameDecoder();
  decoder.push(framed);
  const msg = decoder.next();
  assertEquals(msg, payload);
});

Deno.test("FrameDecoder buffers partial input then completes", () => {
  const payload = { jsonrpc: "2.0" as const, id: 2, method: "shutdown" };
  const framed = encodeFramed(payload);
  const half = Math.floor(framed.byteLength / 2);
  const decoder = new FrameDecoder();
  decoder.push(framed.slice(0, half));
  assertEquals(decoder.next(), null);
  decoder.push(framed.slice(half));
  assertEquals(decoder.next(), payload);
});

Deno.test("FrameDecoder yields multiple messages from one buffer", () => {
  const a = { jsonrpc: "2.0" as const, id: 1, method: "initialize", params: {} };
  const b = { jsonrpc: "2.0" as const, id: 2, method: "shutdown" };
  const decoder = new FrameDecoder();
  decoder.push(encodeFramed(a));
  decoder.push(encodeFramed(b));
  assertEquals(decoder.next(), a);
  assertEquals(decoder.next(), b);
  assertEquals(decoder.next(), null);
});

Deno.test("encodeFramed uses CRLF header terminator", () => {
  const out = encodeFramed({});
  const text = new TextDecoder().decode(out);
  assert(text.includes("\r\n\r\n"));
  assert(text.startsWith("Content-Length: "));
});

Deno.test("dispatch initialize returns server capabilities", async () => {
  const opts = defaultOpts();
  const resp = await dispatch(
    { jsonrpc: "2.0", id: 1, method: "initialize", params: { rootUri: null } },
    opts,
  ) as JsonRpcResponse;
  assertExists(resp);
  assertEquals(resp.id, 1);
  const result = resp.result as {
    capabilities: { hoverProvider: boolean };
    serverInfo: { name: string };
  };
  assertEquals(result.serverInfo.name, "proof-lsp");
  assertEquals(result.capabilities.hoverProvider, true);
});

Deno.test("dispatch unknown method returns -32601", async () => {
  const opts = defaultOpts();
  const resp = await dispatch(
    { jsonrpc: "2.0", id: 99, method: "made/up" },
    opts,
  ) as JsonRpcResponse;
  assertExists(resp);
  assertEquals(resp.error?.code, -32601);
});

Deno.test("dispatch notifications (no id) return null", async () => {
  const opts = defaultOpts();
  const resp = await dispatch(
    { jsonrpc: "2.0", method: "initialized" } as never,
    opts,
  );
  assertEquals(resp, null);
});

Deno.test("dispatch shutdown returns null result", async () => {
  const opts = defaultOpts();
  const resp = await dispatch(
    { jsonrpc: "2.0", id: 7, method: "shutdown" },
    opts,
  ) as JsonRpcResponse;
  assertEquals(resp.result, null);
});

Deno.test("dispatch completion on .v uri returns Coq tactics", async () => {
  const opts = defaultOpts();
  const resp = await dispatch(
    {
      jsonrpc: "2.0",
      id: 3,
      method: "textDocument/completion",
      params: {
        textDocument: { uri: "file:///tmp/example.v" },
        position: { line: 0, character: 0 },
      },
    },
    opts,
  ) as JsonRpcResponse;
  assertExists(resp);
  const list = resp.result as { items: { label: string }[] };
  assert(list.items.length > 0);
  assert(list.items.some((i) => i.label === "intros"));
});

Deno.test("dispatch completion on .lean uri returns Lean tactics", async () => {
  const opts = defaultOpts();
  const resp = await dispatch(
    {
      jsonrpc: "2.0",
      id: 4,
      method: "textDocument/completion",
      params: {
        textDocument: { uri: "file:///tmp/example.lean" },
        position: { line: 0, character: 0 },
      },
    },
    opts,
  ) as JsonRpcResponse;
  const list = resp!.result as { items: { label: string }[] };
  assert(list.items.some((i) => i.label === "intro"));
});

Deno.test("dispatch hover returns null when backend has no info", async () => {
  const opts = defaultOpts();
  const resp = await dispatch(
    {
      jsonrpc: "2.0",
      id: 5,
      method: "textDocument/hover",
      params: {
        textDocument: { uri: "file:///tmp/example.v" },
        position: { line: 0, character: 0 },
      },
    },
    opts,
  ) as JsonRpcResponse;
  assertEquals(resp!.result, null);
});

Deno.test("dispatch executeCommand unknown returns ok=false", async () => {
  const opts = defaultOpts();
  const resp = await dispatch(
    {
      jsonrpc: "2.0",
      id: 6,
      method: "workspace/executeCommand",
      params: {
        command: "proof.nonexistent",
        arguments: ["file:///tmp/x.v"],
      },
    },
    opts,
  ) as JsonRpcResponse;
  const result = resp!.result as { ok: boolean; error?: string };
  assertEquals(result.ok, false);
});

Deno.test("diagnostic on non-proof uri returns empty diagnostics", async () => {
  const opts = defaultOpts();
  const resp = await dispatch(
    {
      jsonrpc: "2.0",
      id: 8,
      method: "textDocument/diagnostic",
      params: { textDocument: { uri: "file:///tmp/README.md" } },
    },
    opts,
  ) as JsonRpcResponse;
  const result = resp!.result as { diagnostics: unknown[] };
  assertEquals(result.diagnostics, []);
});
