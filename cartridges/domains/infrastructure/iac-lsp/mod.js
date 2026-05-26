// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

// iac-lsp host entry point.
//
// Cartridge state: scaffolded. The LSP adapter is not implemented yet — the
// follow-up port from polystack/poly-iac/lsp/ Elixir source (preserved
// in _source-archive/) will fill adapter/server.ts and the per-method handlers.

export const manifest = {
  name: "iac-lsp",
  version: "0.1.0",
  protocols: ["LSP"],
  state: "scaffolded",
  backends: ["opentofu", "pulumi"],
  loopback: { host: "127.0.0.1", port: 5185 },
};

export async function start() {
  throw new Error(
    "iac-lsp adapter not implemented — see _source-archive/ and README.adoc#port-plan",
  );
}

export async function stop() {
  // No-op: nothing to stop while scaffolded.
}
