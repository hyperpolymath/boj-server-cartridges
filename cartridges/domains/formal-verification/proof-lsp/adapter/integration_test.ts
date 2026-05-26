// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

// End-to-end smoke test: spawn the adapter as a subprocess, speak LSP-framed
// JSON-RPC over stdio, verify the initialize handshake.

import { assert, assertEquals } from "@std/assert";
import { dirname, fromFileUrl, join } from "@std/path";
import { encodeFramed, FrameDecoder } from "./server.ts";

Deno.test("end-to-end: spawn adapter and round-trip initialize", async () => {
  const here = dirname(fromFileUrl(import.meta.url));
  const entry = join(here, "server.ts");
  const cmd = new Deno.Command(Deno.execPath(), {
    args: ["run", "--allow-read", "--allow-run", "--allow-env", entry],
    stdin: "piped",
    stdout: "piped",
    stderr: "piped",
  });
  const proc = cmd.spawn();
  const writer = proc.stdin.getWriter();
  const reader = proc.stdout.getReader();

  try {
    const initialize = {
      jsonrpc: "2.0" as const,
      id: 1,
      method: "initialize",
      params: { rootUri: null },
    };
    await writer.write(encodeFramed(initialize));

    const decoder = new FrameDecoder();
    let response = null;
    const deadline = Date.now() + 5000;
    while (Date.now() < deadline) {
      const { value, done } = await reader.read();
      if (done) break;
      decoder.push(value);
      response = decoder.next();
      if (response) break;
    }

    assert(response, "no response from adapter within 5s");
    const resp = response as unknown as {
      id: number;
      result: { serverInfo: { name: string } };
    };
    assertEquals(resp.id, 1);
    assertEquals(resp.result.serverInfo.name, "proof-lsp");

    const exitMsg = {
      jsonrpc: "2.0" as const,
      method: "exit",
    };
    await writer.write(encodeFramed(exitMsg));
  } finally {
    try {
      await writer.close();
    } catch { /* ignore */ }
    try {
      reader.releaseLock();
    } catch { /* ignore */ }
    try {
      await proc.stdout.cancel();
    } catch { /* ignore */ }
    try {
      await proc.stderr.cancel();
    } catch { /* ignore */ }
    try {
      proc.kill("SIGTERM");
    } catch { /* already exited */ }
    await proc.status;
  }
});
