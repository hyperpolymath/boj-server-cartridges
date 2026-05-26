// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

// stack-orchestrator-mcp host entry point.
//
// Cartridge state: scaffolded. The MCP adapter is not implemented yet — the
// port from polystack/poly-orchestrator-lsp/lib/ Elixir source (preserved in
// _source-archive/) will fill adapter/server.ts, the per-tool handlers,
// and the dispatch logic that calls into the 11 coordinated LSP cartridges.
//
// See docs/decisions/ADR-002 for the architecture and the rationale for why
// this is a new cartridge rather than a redesign of the existing fleet-mcp.

export const manifest = {
  name: "stack-orchestrator-mcp",
  version: "0.1.0",
  protocols: ["MCP", "REST"],
  state: "scaffolded",
  coordinated_lsps: [
    "cloud-lsp",
    "container-lsp",
    "database-lsp",
    "k8s-lsp",
    "git-lsp",
    "iac-lsp",
    "observe-lsp",
    "queues-lsp",
    "secrets-lsp",
    "ssg-lsp",
    "proof-lsp",
  ],
  loopback: { host: "127.0.0.1", port: 5190 },
};

export async function start() {
  throw new Error(
    "stack-orchestrator-mcp adapter not implemented — see _source-archive/ " +
      "and README.adoc#port-plan, ADR-002 for the architecture decision.",
  );
}

export async function stop() {
  // No-op: nothing to stop while scaffolded.
}
