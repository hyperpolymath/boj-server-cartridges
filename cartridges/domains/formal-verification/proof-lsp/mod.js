import { Command } from "../../../lib/process.js";
// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

// proof-lsp host entry point.
//
// Cartridge state: adapter-implemented. start() spawns the Deno adapter
// at adapter/server.ts which speaks LSP over stdio.

import { dirname, join } from "node:path";
import { fileURLToPath as fromFileUrl } from "node:url";

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
  const entry = join(here, "adapter", "server.js");
  const cmd = new Command(process.execPath, {
    args: ["run", entry],
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
