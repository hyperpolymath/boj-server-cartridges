// SPDX-License-Identifier: MPL-2.0
const VERSION = "0.1.0", CAPABILITIES = {
  textDocumentSync: { openClose: !0, change: 1, save: { includeText: !1 } },
  completionProvider: {
    triggerCharacters: [" ", "(", "{", "[", ":"],
    resolveProvider: !1
  },
  hoverProvider: !0,
  diagnosticProvider: { interFileDependencies: !1, workspaceDiagnostics: !1 },
  executeCommandProvider: {
    commands: [
      "proof.check",
      "proof.showGoals",
      "proof.applyTactic",
      "proof.searchTheorem"
    ]
  }
};
function uriToPath(uri) {
  if (!uri)
    return null;
  if (uri.startsWith("file://"))
    return decodeURIComponent(uri.slice(7));
  return uri;
}
export async function handleInitialize(params, backends) {
  const rootPath = uriToPath(params.rootUri);
  let detected = null;
  if (rootPath)
    for (const backend of backends.values()) {
      const r = await backend.detect(rootPath);
      if (r.ok && r.value) {
        detected = backend.id;
        break;
      }
    }
  return {
    capabilities: CAPABILITIES,
    serverInfo: { name: "proof-lsp", version: VERSION },
    detectedBackend: detected
  };
}
