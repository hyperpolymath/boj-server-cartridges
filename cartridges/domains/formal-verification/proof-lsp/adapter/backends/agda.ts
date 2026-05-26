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

export class AgdaBackend implements Backend {
  readonly id = "agda" as const;
  readonly binary = "agda";
  readonly extensions = [".agda", ".lagda"] as const;

  async detect(projectPath: string): Promise<Result<boolean>> {
    try {
      for await (const entry of Deno.readDir(projectPath)) {
        if (
          entry.isFile &&
          (entry.name.endsWith(".agda") || entry.name.endsWith(".lagda"))
        ) {
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
    if (!filePath.endsWith(".agda") && !filePath.endsWith(".lagda")) {
      return { ok: true, value: [] };
    }

    const result = await runChecker(this.binary, [filePath]);
    if (!result.ok) return result;
    const { stdout, stderr, code } = result.value;
    if (code === 0) return { ok: true, value: [] };

    const combined = `${stderr}\n${stdout}`;
    const diagnostics: LspDiagnostic[] = [];
    const locRe = /^([^:]+):(\d+),(\d+)(?:-(\d+),(\d+))?:?/;
    for (const line of combined.split("\n").slice(0, 50)) {
      const m = line.match(locRe);
      if (m) {
        const startLine = parseInt(m[2]!, 10) - 1;
        const startCol = parseInt(m[3]!, 10) - 1;
        diagnostics.push({
          range: {
            start: { line: startLine, character: startCol },
            end: { line: startLine, character: startCol + 1 },
          },
          severity: 1,
          source: "proof-lsp:agda",
          message: line.trim(),
        });
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
      "record",
      "data",
      "where",
      "module",
      "import",
      "open",
      "private",
      "postulate",
      "refl",
      "rewrite",
    ];
    return Promise.resolve({
      ok: true,
      value: items.map((label) => ({
        label,
        kind: 14,
        detail: "Agda keyword",
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
