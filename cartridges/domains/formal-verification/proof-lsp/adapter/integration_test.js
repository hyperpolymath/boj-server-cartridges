// SPDX-License-Identifier: MPL-2.0
import { test } from "bun:test";
import { Command } from "../../../../lib/process.js";
import { ok as assert, deepStrictEqual as assertEquals } from "node:assert/strict";
import { dirname, join } from "node:path";
import { fileURLToPath as fromFileUrl } from "node:url";
import { encodeFramed, FrameDecoder } from "./server.js";
test("end-to-end: spawn adapter and round-trip initialize", async () => {
  const here = dirname(fromFileUrl(import.meta.url)), entry = join(here, "server.js"), proc = new Command(process.execPath, {
    args: ["run", entry],
    stdin: "piped",
    stdout: "piped",
    stderr: "piped"
  }).spawn(), writer = proc.stdin.getWriter(), reader = proc.stdout.getReader();
  try {
    const initialize = {
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: { rootUri: null }
    };
    await writer.write(encodeFramed(initialize));
    const decoder = new FrameDecoder;
    let response = null;
    const deadline = Date.now() + 5000;
    while (Date.now() < deadline) {
      const { value, done } = await reader.read();
      if (done)
        break;
      decoder.push(value);
      response = decoder.next();
      if (response)
        break;
    }
    assert(response, "no response from adapter within 5s");
    const resp = response;
    assertEquals(resp.id, 1);
    assertEquals(resp.result.serverInfo.name, "proof-lsp");
    const exitMsg = {
      jsonrpc: "2.0",
      method: "exit"
    };
    await writer.write(encodeFramed(exitMsg));
  } finally {
    try {
      await writer.close();
    } catch {}
    try {
      reader.releaseLock();
    } catch {}
    try {
      await proc.stdout.cancel();
    } catch {}
    try {
      await proc.stderr.cancel();
    } catch {}
    try {
      proc.kill("SIGTERM");
    } catch {}
    await proc.status;
  }
});
