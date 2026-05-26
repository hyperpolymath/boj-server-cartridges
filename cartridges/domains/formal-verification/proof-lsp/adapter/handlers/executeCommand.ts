// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

import type { Backend } from "../backends/base.ts";
import { detectByExtension } from "../backends/registry.ts";
import type { BackendId, LspDiagnostic } from "../types.ts";

export interface ExecuteCommandParams {
  command: string;
  arguments?: unknown[];
}

export interface ExecuteCommandResult {
  command: string;
  ok: boolean;
  data?: unknown;
  error?: string;
}

export async function handleExecuteCommand(
  params: ExecuteCommandParams,
  backends: Map<BackendId, Backend>,
): Promise<ExecuteCommandResult> {
  const args = params.arguments ?? [];
  const uri = typeof args[0] === "string" ? args[0] : "";
  const backendHint = typeof args[1] === "string"
    ? args[1] as BackendId
    : undefined;
  const explicit = backendHint ? backends.get(backendHint) : undefined;
  const backend = explicit ?? detectByExtension(backends, uri);

  if (!backend) {
    return {
      command: params.command,
      ok: false,
      error: "No proof backend detected for URI",
    };
  }

  switch (params.command) {
    case "proof.check": {
      const r = await backend.lint(uri);
      if (!r.ok) return { command: params.command, ok: false, error: r.error };
      const diagnostics: LspDiagnostic[] = r.value;
      return {
        command: params.command,
        ok: diagnostics.length === 0,
        data: { backend: backend.id, diagnostics },
      };
    }
    case "proof.showGoals": {
      return {
        command: params.command,
        ok: true,
        data: {
          backend: backend.id,
          note:
            "interactive-only — implemented per-backend in subsequent revisions",
        },
      };
    }
    case "proof.applyTactic": {
      return {
        command: params.command,
        ok: true,
        data: {
          backend: backend.id,
          note: "tactic application requires interactive session",
        },
      };
    }
    case "proof.searchTheorem": {
      return {
        command: params.command,
        ok: true,
        data: { backend: backend.id, results: [] },
      };
    }
    default:
      return {
        command: params.command,
        ok: false,
        error: `Unknown command: ${params.command}`,
      };
  }
}
