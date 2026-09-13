// SPDX-License-Identifier: MPL-2.0
export const cartridge = {
  name: "academic-workflow-mcp",
  version: "1.0.0",
  description: "Academic workflow cartridge",
  tools: [
    { id: "search_zotero", name: "Search Zotero" },
    { id: "get_paper_metadata", name: "Get Paper Metadata" },
    { id: "generate_citation", name: "Generate Citation" },
    { id: "extract_bibkeys", name: "Extract BibTeX Keys" },
    { id: "export_collection", name: "Export Collection" },
    { id: "add_review_note", name: "Add Review Note" },
  ],
};

export async function health() {
  return { status: "unavailable", cartridge: "academic-workflow-mcp" };
}

export async function init() {
  console.log("[academic-workflow-mcp] Initializing");
  return { initialized: false, error: "JavaScript adapter not implemented" };
}

export async function cleanup() {
  console.log("[academic-workflow-mcp] Shutting down");
  return { cleaned: true };
}

// Explicit refusal: this legacy JS surface has no implemented tool transport.
export async function handleTool() {
  return {status: 501, data: {success: false, error: "JavaScript adapter not implemented"}};
}
