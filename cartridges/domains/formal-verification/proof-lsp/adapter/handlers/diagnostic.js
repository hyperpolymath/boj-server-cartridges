// SPDX-License-Identifier: MPL-2.0
import { detectByExtension } from "../backends/registry.js";
export async function handleDiagnostic(params, backends) {
  const uri = params.textDocument?.uri ?? "", backend = (params.backend ? backends.get(params.backend) : void 0) ?? detectByExtension(backends, uri);
  if (!backend)
    return { uri, diagnostics: [] };
  if (!await backend.available())
    return {
      uri,
      diagnostics: [{
        range: {
          start: { line: 0, character: 0 },
          end: { line: 0, character: 0 }
        },
        severity: 3,
        source: `proof-lsp:${backend.id}`,
        message: `Backend binary "${backend.binary}" not available in PATH`
      }]
    };
  const lint = await backend.lint(uri);
  if (!lint.ok)
    return {
      uri,
      diagnostics: [{
        range: {
          start: { line: 0, character: 0 },
          end: { line: 0, character: 0 }
        },
        severity: 1,
        source: `proof-lsp:${backend.id}`,
        message: lint.error
      }]
    };
  return { uri, diagnostics: lint.value };
}
