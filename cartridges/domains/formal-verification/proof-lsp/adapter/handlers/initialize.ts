// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

import type { Backend } from "../backends/base.ts";
import type { BackendId } from "../types.ts";

export interface InitializeParams {
  rootUri?: string | null;
  capabilities?: Record<string, unknown>;
}

export interface ServerCapabilities {
  textDocumentSync: { openClose: boolean; change: number; save: { includeText: boolean } };
  completionProvider: { triggerCharacters: string[]; resolveProvider: boolean };
  hoverProvider: boolean;
  diagnosticProvider: { interFileDependencies: boolean; workspaceDiagnostics: boolean };
  executeCommandProvider: { commands: string[] };
}

export interface InitializeResult {
  capabilities: ServerCapabilities;
  serverInfo: { name: string; version: string };
  detectedBackend: BackendId | null;
}

const VERSION = "0.1.0";

const CAPABILITIES: ServerCapabilities = {
  textDocumentSync: { openClose: true, change: 1, save: { includeText: false } },
  completionProvider: {
    triggerCharacters: [" ", "(", "{", "[", ":"],
    resolveProvider: false,
  },
  hoverProvider: true,
  diagnosticProvider: { interFileDependencies: false, workspaceDiagnostics: false },
  executeCommandProvider: {
    commands: [
      "proof.check",
      "proof.showGoals",
      "proof.applyTactic",
      "proof.searchTheorem",
    ],
  },
};

function uriToPath(uri: string | null | undefined): string | null {
  if (!uri) return null;
  if (uri.startsWith("file://")) return decodeURIComponent(uri.slice(7));
  return uri;
}

export async function handleInitialize(
  params: InitializeParams,
  backends: Map<BackendId, Backend>,
): Promise<InitializeResult> {
  const rootPath = uriToPath(params.rootUri);
  let detected: BackendId | null = null;

  if (rootPath) {
    for (const backend of backends.values()) {
      const r = await backend.detect(rootPath);
      if (r.ok && r.value) {
        detected = backend.id;
        break;
      }
    }
  }

  return {
    capabilities: CAPABILITIES,
    serverInfo: { name: "proof-lsp", version: VERSION },
    detectedBackend: detected,
  };
}
