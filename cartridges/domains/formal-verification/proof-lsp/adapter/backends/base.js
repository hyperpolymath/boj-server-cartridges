// SPDX-License-Identifier: MPL-2.0
import { Command } from "../../../../../lib/process.js";
export async function whichBinary(binary) {
  try {
    const cmd = new Command(binary, {
      args: ["--version"],
      stdout: "null",
      stderr: "null"
    }), { code } = await cmd.output();
    return code === 0;
  } catch {
    return !1;
  }
}
export async function runChecker(binary, args, opts = {}) {
  try {
    const proc = new Command(binary, {
      args,
      cwd: opts.cwd,
      stdout: "piped",
      stderr: "piped"
    }).spawn(), timeout = opts.timeoutMs ?? 30000, timer = setTimeout(() => {
      try {
        proc.kill("SIGKILL");
      } catch {}
    }, timeout);
    let out;
    try { out = await proc.output(); } finally { clearTimeout(timer); }
    return {
      ok: !0,
      value: {
        stdout: new TextDecoder().decode(out.stdout),
        stderr: new TextDecoder().decode(out.stderr),
        code: out.code
      }
    };
  } catch (e) {
    return { ok: !1, error: `${binary} not available: ${String(e)}` };
  }
}
export function filePathFromUri(uri) {
  if (uri.startsWith("file://"))
    return decodeURIComponent(uri.slice(7));
  return uri;
}
export function diagnosticAtLine(message, severity, source, line = 0) {
  return {
    range: {
      start: { line, character: 0 },
      end: { line, character: 200 }
    },
    severity,
    source,
    message: message.trim()
  };
}
