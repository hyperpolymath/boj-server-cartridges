// SPDX-License-Identifier: MPL-2.0
// Hesiod DNS Cartridge — Entry point for BoJ integration

/**
 * Cartridge metadata (populated from cartridge.json at runtime)
 */
export const cartridge = {
  name: "hesiod-mcp",
  version: "1.0.0",
  description: "DNS lookup cartridge",
  tools: [
    {
      id: "dns_lookup",
      name: "DNS Lookup",
      invoke: async (args) => {
        // Calls adapter/mod.ts which bridges to Zig FFI
        return await invokeTool("dns_lookup", args);
      },
    },
    {
      id: "dns_reverse_lookup",
      name: "Reverse DNS Lookup",
      invoke: async (args) => {
        return await invokeTool("dns_reverse_lookup", args);
      },
    },
    {
      id: "dns_bulk_lookup",
      name: "Bulk DNS Lookup",
      invoke: async (args) => {
        return await invokeTool("dns_bulk_lookup", args);
      },
    },
  ],
};

/**
 * Tool invocation handler
 * Routes MCP tool calls to the appropriate handler via the Deno adapter
 */
async function invokeTool() {
  return {success: false, error: "JavaScript DNS adapter not implemented"};
}

/**
 * Cartridge health check
 */
export async function health() {
  return {
    status: "unavailable",
    cartridge: "hesiod-mcp",
    loopback: "127.0.0.1:5173",
    tools: cartridge.tools.length,
  };
}

/**
 * Cartridge initialization hook
 */
export async function init() {
  console.log(`[hesiod-mcp] Initializing DNS lookup cartridge`);
  // Would load Zig FFI, validate loopback proof, etc.
  return { initialized: false, error: "JavaScript adapter not implemented" };
}

/**
 * Cartridge teardown hook
 */
export async function cleanup() {
  console.log(`[hesiod-mcp] Shutting down`);
  return { cleaned: true };
}

// Explicit refusal: this legacy JS surface has no implemented tool transport.
export async function handleTool() {
  return {status: 501, data: {success: false, error: "JavaScript adapter not implemented"}};
}
