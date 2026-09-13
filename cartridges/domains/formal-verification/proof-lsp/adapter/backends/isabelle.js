// SPDX-License-Identifier: MPL-2.0
import { readDir } from "../../../../../lib/files.js";
import {
  diagnosticAtLine,
  filePathFromUri,
  runChecker,
  whichBinary
} from "./base.js";

export class IsabelleBackend {
  id = "isabelle";
  binary = "isabelle";
  extensions = [".thy"];
  async detect(projectPath) {
    try {
      for await (const entry of readDir(projectPath))
        if (entry.isFile && entry.name.endsWith(".thy"))
          return { ok: !0, value: !0 };
      return { ok: !0, value: !1 };
    } catch (e) {
      return { ok: !1, error: String(e) };
    }
  }
  available() {
    return whichBinary(this.binary);
  }
  async lint(uri) {
    if (!filePathFromUri(uri).endsWith(".thy"))
      return { ok: !0, value: [] };
    return Promise.resolve({
      ok: !0,
      value: [
        diagnosticAtLine("Isabelle requires an interactive PIDE session for proof checking.", 3, "proof-lsp:isabelle")
      ]
    });
  }
  hover(_uri, _pos) {
    return Promise.resolve({ ok: !0, value: null });
  }
  complete(_uri, _pos) {
    return Promise.resolve({
      ok: !0,
      value: [
        "lemma",
        "theorem",
        "definition",
        "fun",
        "primrec",
        "proof",
        "qed",
        "by",
        "apply",
        "done"
      ].map((label) => ({
        label,
        kind: 14,
        detail: "Isabelle keyword"
      }))
    });
  }
  async version() {
    const r = await runChecker(this.binary, ["version"]);
    if (!r.ok)
      return r;
    return { ok: !0, value: r.value.stdout.trim() };
  }
}
