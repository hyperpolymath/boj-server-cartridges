// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

import type { Backend } from "../backends/base.ts";
import { detectByExtension } from "../backends/registry.ts";
import type { BackendId, LspDiagnostic } from "../types.ts";

export interface DiagnosticParams {
  textDocument: { uri: string };
  backend?: BackendId;
}

export interface DiagnosticResult {
  uri: string;
  diagnostics: LspDiagnostic[];
}

export async function handleDiagnostic(
  params: DiagnosticParams,
  backends: Map<BackendId, Backend>,
): Promise<DiagnosticResult> {
  const uri = params.textDocument?.uri ?? "";
  const explicit = params.backend ? backends.get(params.backend) : undefined;
  const backend = explicit ?? detectByExtension(backends, uri);
  if (!backend) return { uri, diagnostics: [] };

  if (!(await backend.available())) {
    return {
      uri,
      diagnostics: [{
        range: {
          start: { line: 0, character: 0 },
          end: { line: 0, character: 0 },
        },
        severity: 3,
        source: `proof-lsp:${backend.id}`,
        message: `Backend binary "${backend.binary}" not available in PATH`,
      }],
    };
  }

  const lint = await backend.lint(uri);
  if (!lint.ok) {
    return {
      uri,
      diagnostics: [{
        range: {
          start: { line: 0, character: 0 },
          end: { line: 0, character: 0 },
        },
        severity: 1,
        source: `proof-lsp:${backend.id}`,
        message: lint.error,
      }],
    };
  }
  return { uri, diagnostics: lint.value };
}
