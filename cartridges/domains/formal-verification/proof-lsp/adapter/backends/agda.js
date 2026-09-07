// SPDX-License-Identifier: MPL-2.0
import { readDir } from "../../../../../lib/files.js";
import {
  diagnosticAtLine,
  filePathFromUri,
  runChecker,
  whichBinary
} from "./base.js";

export class AgdaBackend {
  id = "agda";
  binary = "agda";
  extensions = [".agda", ".lagda"];
  async detect(projectPath) {
    try {
      for await (const entry of readDir(projectPath))
        if (entry.isFile && (entry.name.endsWith(".agda") || entry.name.endsWith(".lagda")))
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
    if (!filePath.endsWith(".agda") && !filePath.endsWith(".lagda"))
      return { ok: !0, value: [] };
    const result = await runChecker(this.binary, [filePath]);
    if (!result.ok)
      return result;
    const { stdout, stderr, code } = result.value;
    if (code === 0)
      return { ok: !0, value: [] };
    const combined = `${stderr}
${stdout}`, diagnostics = [], locRe = /^([^:]+):(\d+),(\d+)(?:-(\d+),(\d+))?:?/;
    for (const line of combined.split(`
`).slice(0, 50)) {
      const m = line.match(locRe);
      if (m) {
        const startLine = parseInt(m[2], 10) - 1, startCol = parseInt(m[3], 10) - 1;
        diagnostics.push({
          range: {
            start: { line: startLine, character: startCol },
            end: { line: startLine, character: startCol + 1 }
          },
          severity: 1,
          source: "proof-lsp:agda",
          message: line.trim()
        });
      }
    }
    return { ok: !0, value: diagnostics };
  }
  hover(_uri, _pos) {
    return Promise.resolve({ ok: !0, value: null });
  }
  complete(_uri, _pos) {
    return Promise.resolve({
      ok: !0,
      value: [
        "record",
        "data",
        "where",
        "module",
        "import",
        "open",
        "private",
        "postulate",
        "refl",
        "rewrite"
      ].map((label) => ({
        label,
        kind: 14,
        detail: "Agda keyword"
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
