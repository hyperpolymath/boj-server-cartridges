// SPDX-License-Identifier: MPL-2.0
import { test } from "bun:test";
import { ok as assert, deepStrictEqual as assertEquals, ok as assertExists } from "node:assert/strict";
import {
  defaultOpts,
  dispatch,
  encodeFramed,
  FrameDecoder
} from "./server.js";
test("FrameDecoder decodes a single framed message", () => {
  const payload = { jsonrpc: "2.0", id: 1, method: "initialize", params: {} }, framed = encodeFramed(payload), decoder = new FrameDecoder;
  decoder.push(framed);
  const msg = decoder.next();
  assertEquals(msg, payload);
});
test("FrameDecoder buffers partial input then completes", () => {
  const payload = { jsonrpc: "2.0", id: 2, method: "shutdown" }, framed = encodeFramed(payload), half = Math.floor(framed.byteLength / 2), decoder = new FrameDecoder;
  decoder.push(framed.slice(0, half));
  assertEquals(decoder.next(), null);
  decoder.push(framed.slice(half));
  assertEquals(decoder.next(), payload);
});
test("FrameDecoder yields multiple messages from one buffer", () => {
  const a = { jsonrpc: "2.0", id: 1, method: "initialize", params: {} }, b = { jsonrpc: "2.0", id: 2, method: "shutdown" }, decoder = new FrameDecoder;
  decoder.push(encodeFramed(a));
  decoder.push(encodeFramed(b));
  assertEquals(decoder.next(), a);
  assertEquals(decoder.next(), b);
  assertEquals(decoder.next(), null);
});
test("encodeFramed uses CRLF header terminator", () => {
  const out = encodeFramed({}), text = new TextDecoder().decode(out);
  assert(text.includes(`\r
\r
`));
  assert(text.startsWith("Content-Length: "));
});
test("dispatch initialize returns server capabilities", async () => {
  const opts = defaultOpts(), resp = await dispatch({ jsonrpc: "2.0", id: 1, method: "initialize", params: { rootUri: null } }, opts);
  assertExists(resp);
  assertEquals(resp.id, 1);
  const result = resp.result;
  assertEquals(result.serverInfo.name, "proof-lsp");
  assertEquals(result.capabilities.hoverProvider, !0);
});
test("dispatch unknown method returns -32601", async () => {
  const opts = defaultOpts(), resp = await dispatch({ jsonrpc: "2.0", id: 99, method: "made/up" }, opts);
  assertExists(resp);
  assertEquals(resp.error?.code, -32601);
});
test("dispatch notifications (no id) return null", async () => {
  const opts = defaultOpts(), resp = await dispatch({ jsonrpc: "2.0", method: "initialized" }, opts);
  assertEquals(resp, null);
});
test("dispatch shutdown returns null result", async () => {
  const opts = defaultOpts(), resp = await dispatch({ jsonrpc: "2.0", id: 7, method: "shutdown" }, opts);
  assertEquals(resp.result, null);
});
test("dispatch completion on .v uri returns Coq tactics", async () => {
  const opts = defaultOpts(), resp = await dispatch({
    jsonrpc: "2.0",
    id: 3,
    method: "textDocument/completion",
    params: {
      textDocument: { uri: "file:///tmp/example.v" },
      position: { line: 0, character: 0 }
    }
  }, opts);
  assertExists(resp);
  const list = resp.result;
  assert(list.items.length > 0);
  assert(list.items.some((i) => i.label === "intros"));
});
test("dispatch completion on .lean uri returns Lean tactics", async () => {
  const opts = defaultOpts(), list = (await dispatch({
    jsonrpc: "2.0",
    id: 4,
    method: "textDocument/completion",
    params: {
      textDocument: { uri: "file:///tmp/example.lean" },
      position: { line: 0, character: 0 }
    }
  }, opts)).result;
  assert(list.items.some((i) => i.label === "intro"));
});
test("dispatch hover returns null when backend has no info", async () => {
  const opts = defaultOpts(), resp = await dispatch({
    jsonrpc: "2.0",
    id: 5,
    method: "textDocument/hover",
    params: {
      textDocument: { uri: "file:///tmp/example.v" },
      position: { line: 0, character: 0 }
    }
  }, opts);
  assertEquals(resp.result, null);
});
test("dispatch executeCommand unknown returns ok=false", async () => {
  const opts = defaultOpts(), result = (await dispatch({
    jsonrpc: "2.0",
    id: 6,
    method: "workspace/executeCommand",
    params: {
      command: "proof.nonexistent",
      arguments: ["file:///tmp/x.v"]
    }
  }, opts)).result;
  assertEquals(result.ok, !1);
});
test("diagnostic on non-proof uri returns empty diagnostics", async () => {
  const opts = defaultOpts(), result = (await dispatch({
    jsonrpc: "2.0",
    id: 8,
    method: "textDocument/diagnostic",
    params: { textDocument: { uri: "file:///tmp/README.md" } }
  }, opts)).result;
  assertEquals(result.diagnostics, []);
});
