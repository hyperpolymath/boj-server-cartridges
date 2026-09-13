// SPDX-License-Identifier: MPL-2.0
export const cartridge = {
  name: "sanctify-mcp",
  version: "1.0.0",
  description: "Sanctify cartridge — PHP lint and deviation detection",
  tools: [
    { id: "lint_file", name: "Lint File" },
    { id: "detect_deviations", name: "Detect Deviations" },
    { id: "analyze_file", name: "Analyze File" },
    { id: "check_snippet", name: "Check Snippet" },
    { id: "validate_syntax", name: "Validate Syntax" },
  ],
};

export async function health() {
  return { status: "unavailable", cartridge: "sanctify-mcp" };
}

export async function init() {
  console.log("[sanctify-mcp] Initializing");
  return { initialized: false, error: "JavaScript adapter not implemented" };
}

export async function cleanup() {
  console.log("[sanctify-mcp] Shutting down");
  return { cleaned: true };
}

// Explicit refusal: this legacy JS surface has no implemented tool transport.
export async function handleTool() {
  return {status: 501, data: {success: false, error: "JavaScript adapter not implemented"}};
}
