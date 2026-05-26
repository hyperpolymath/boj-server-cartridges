// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

// cloud-lsp host entry point.
//
// Cartridge state: scaffolded. The LSP adapter is not implemented yet — the
// follow-up port from polystack/poly-cloud/lsp/ Elixir source (preserved
// in _source-archive/) will fill adapter/server.ts and the per-method handlers.

export const manifest = {
  name: "cloud-lsp",
  version: "0.1.0",
  protocols: ["LSP"],
  state: "scaffolded",
  backends: ["aws", "azure", "gcp", "digitalocean"],
  loopback: { host: "127.0.0.1", port: 5180 },
};

export async function start() {
  throw new Error(
    "cloud-lsp adapter not implemented — see _source-archive/ and README.adoc#port-plan",
  );
}

export async function stop() {
  // No-op: nothing to stop while scaffolded.
}
