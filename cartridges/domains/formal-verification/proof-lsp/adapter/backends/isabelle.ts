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

export class IsabelleBackend implements Backend {
  readonly id = "isabelle" as const;
  readonly binary = "isabelle";
  readonly extensions = [".thy"] as const;

  async detect(projectPath: string): Promise<Result<boolean>> {
    try {
      for await (const entry of Deno.readDir(projectPath)) {
        if (entry.isFile && entry.name.endsWith(".thy")) {
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
    if (!filePath.endsWith(".thy")) return { ok: true, value: [] };

    // Isabelle theory checking requires an interactive session (PIDE).
    // Surface a single info diagnostic noting that batch lint is unavailable;
    // a full implementation would speak to an isabelle/jedit or isabelle-server
    // process. See README.adoc#port-plan.
    return Promise.resolve({
      ok: true,
      value: [
        diagnosticAtLine(
          "Isabelle requires an interactive PIDE session for proof checking.",
          3,
          "proof-lsp:isabelle",
        ),
      ],
    });
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
      "lemma",
      "theorem",
      "definition",
      "fun",
      "primrec",
      "proof",
      "qed",
      "by",
      "apply",
      "done",
    ];
    return Promise.resolve({
      ok: true,
      value: items.map((label) => ({
        label,
        kind: 14,
        detail: "Isabelle keyword",
      })),
    });
  }

  async version(): Promise<Result<string>> {
    const r = await runChecker(this.binary, ["version"]);
    if (!r.ok) return r;
    return { ok: true, value: r.value.stdout.trim() };
  }
}
