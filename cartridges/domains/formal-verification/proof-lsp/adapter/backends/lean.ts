// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

import type {
  LspCompletionItem,
  LspDiagnostic,
  LspHover,
  LspPosition,
  Result,
} from "../types.ts";
import {
  type Backend,
  diagnosticAtLine,
  filePathFromUri,
  runChecker,
  whichBinary,
} from "./base.ts";

export class LeanBackend implements Backend {
  readonly id = "lean" as const;
  readonly binary = "lean";
  readonly extensions = [".lean"] as const;

  async detect(projectPath: string): Promise<Result<boolean>> {
    try {
      for await (const entry of Deno.readDir(projectPath)) {
        if (entry.isFile && entry.name.endsWith(".lean")) {
          return { ok: true, value: true };
        }
      }
      return { ok: true, value: false };
    } catch (e) {
      return { ok: false, error: String(e) };
    }
  }

  available(): Promise<boolean> {
    return whichBinary(this.binary);
  }

  async lint(uri: string): Promise<Result<LspDiagnostic[]>> {
    const filePath = filePathFromUri(uri);
    if (!filePath.endsWith(".lean")) return { ok: true, value: [] };

    const result = await runChecker(this.binary, ["--make", filePath]);
    if (!result.ok) return result;
    const { stdout, stderr, code } = result.value;
    if (code === 0) return { ok: true, value: [] };

    const combined = `${stderr}\n${stdout}`;
    const diagnostics: LspDiagnostic[] = [];
    for (const line of combined.split("\n").slice(0, 50)) {
      if (line.includes("error:")) {
        diagnostics.push(diagnosticAtLine(line, 1, "proof-lsp:lean"));
      } else if (line.includes("warning:")) {
        diagnostics.push(diagnosticAtLine(line, 2, "proof-lsp:lean"));
      }
    }
    return { ok: true, value: diagnostics };
  }

  hover(
    _uri: string,
    _pos: LspPosition,
  ): Promise<Result<LspHover | null>> {
    return Promise.resolve({ ok: true, value: null });
  }

  complete(
    _uri: string,
    _pos: LspPosition,
  ): Promise<Result<LspCompletionItem[]>> {
    const items = [
      "intro",
      "exact",
      "apply",
      "rw",
      "simp",
      "constructor",
      "induction",
      "cases",
      "refl",
      "trivial",
    ];
    return Promise.resolve({
      ok: true,
      value: items.map((label) => ({
        label,
        kind: 14,
        detail: "Lean tactic",
      })),
    });
  }

  async version(): Promise<Result<string>> {
    const r = await runChecker(this.binary, ["--version"]);
    if (!r.ok) return r;
    const first = r.value.stdout.split("\n")[0]?.trim() ?? "";
    return { ok: true, value: first };
  }
}
