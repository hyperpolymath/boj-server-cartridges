// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

// proof-lsp host entry point.
//
// Cartridge state: scaffolded. The LSP adapter is not implemented yet — the
// follow-up port from polystack/poly-proof/lsp/ Elixir source (preserved in
// _source-archive/) will fill adapter/server.ts and the per-method handlers.
//
// Until that lands, this module exports a manifest-only surface so the
// BoJ catalog can register the cartridge and surface it to clients with a
// "not ready" capability.

export const manifest = {
  name: "proof-lsp",
  version: "0.1.0",
  protocols: ["LSP"],
  state: "scaffolded",
  backends: ["coq", "lean", "isabelle", "agda"],
  loopback: { host: "127.0.0.1", port: 5179 },
};

export async function start() {
  throw new Error(
    "proof-lsp adapter not implemented — see _source-archive/ and README.adoc#port-plan",
  );
}

export async function stop() {
  // No-op: nothing to stop while scaffolded.
}
