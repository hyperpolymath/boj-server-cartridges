// SPDX-License-Identifier: MPL-2.0
import { detectByExtension } from "../backends/registry.js";
export async function handleExecuteCommand(params, backends) {
  const args = params.arguments ?? [], uri = typeof args[0] === "string" ? args[0] : "", backendHint = typeof args[1] === "string" ? args[1] : void 0, backend = (backendHint ? backends.get(backendHint) : void 0) ?? detectByExtension(backends, uri);
  if (!backend)
    return {
      command: params.command,
      ok: !1,
      error: "No proof backend detected for URI"
    };
  switch (params.command) {
    case "proof.check": {
      const r = await backend.lint(uri);
      if (!r.ok)
        return { command: params.command, ok: !1, error: r.error };
      const diagnostics = r.value;
      return {
        command: params.command,
        ok: diagnostics.length === 0,
        data: { backend: backend.id, diagnostics }
      };
    }
    case "proof.showGoals":
    case "proof.applyTactic":
    case "proof.searchTheorem":
      return {command: params.command, ok: false, error: "unsupported: interactive proof session is not implemented"};
    default:
      return {
        command: params.command,
        ok: !1,
        error: `Unknown command: ${params.command}`
      };
  }
}
