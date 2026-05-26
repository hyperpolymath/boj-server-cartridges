// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

// proof-lsp host entry point.
//
// Cartridge state: adapter-implemented. start() spawns the Deno adapter
// at adapter/server.ts which speaks LSP over stdio.

import { dirname, fromFileUrl, join } from "jsr:@std/path@1";

export const manifest = {
  name: "proof-lsp",
  version: "0.1.0",
  protocols: ["LSP"],
  state: "adapter-implemented",
  backends: ["coq", "lean", "isabelle", "agda"],
  loopback: { host: "127.0.0.1", port: 5179 },
};

let child = null;

export async function start() {
  if (child) return child;
  const here = dirname(fromFileUrl(import.meta.url));
  const entry = join(here, "adapter", "server.ts");
  const cmd = new Deno.Command(Deno.execPath(), {
    args: ["run", "--allow-read", "--allow-run", "--allow-env", entry],
    stdin: "piped",
    stdout: "piped",
    stderr: "inherit",
  });
  child = cmd.spawn();
  return child;
}

export async function stop() {
  if (!child) return;
  try {
    child.kill("SIGTERM");
    await child.status;
  } finally {
    child = null;
  }
}
