// SPDX-License-Identifier: MPL-2.0
import { readDir } from "../../../../../lib/files.js";
import {
  diagnosticAtLine,
  filePathFromUri,
  runChecker,
  whichBinary
} from "./base.js";

export class CoqBackend {
  id = "coq";
  binary = "coqc";
  extensions = [".v"];
  async detect(projectPath) {
    try {
      for await (const entry of readDir(projectPath))
        if (entry.isFile && entry.name.endsWith(".v"))
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
    const filePath = filePathFromUri(uri);
    if (!filePath.endsWith(".v"))
      return { ok: !0, value: [] };
    const result = await runChecker(this.binary, ["-q", filePath]);
    if (!result.ok)
      return result;
    const { stdout, stderr, code } = result.value;
    if (code === 0)
      return { ok: !0, value: [] };
    const combined = `${stderr}
${stdout}`, diagnostics = [];
    for (const line of combined.split(`
`).slice(0, 50))
      if (line.includes("Error:"))
        diagnostics.push(diagnosticAtLine(line, 1, "proof-lsp:coq"));
      else if (line.includes("Warning:"))
        diagnostics.push(diagnosticAtLine(line, 2, "proof-lsp:coq"));
    return { ok: !0, value: diagnostics };
  }
  hover(_uri, _pos) {
    return Promise.resolve({ ok: !0, value: null });
  }
  complete(_uri, _pos) {
    return Promise.resolve({
      ok: !0,
      value: [
        "intros",
        "apply",
        "exact",
        "rewrite",
        "induction",
        "destruct",
        "reflexivity",
        "simpl",
        "auto",
        "omega"
      ].map((label) => ({
        label,
        kind: 14,
        detail: "Coq tactic"
      }))
    });
  }
  async version() {
    const r = await runChecker(this.binary, ["--version"]);
    if (!r.ok)
      return r;
    return { ok: !0, value: r.value.stdout.split(`
`)[0]?.trim() ?? "" };
  }
}
