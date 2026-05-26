// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

import type {
  BackendId,
  LspCompletionItem,
  LspDiagnostic,
  LspHover,
  LspPosition,
  Result,
} from "../types.ts";

export interface Backend {
  readonly id: BackendId;
  readonly binary: string;
  readonly extensions: readonly string[];

  detect(projectPath: string): Promise<Result<boolean>>;
  available(): Promise<boolean>;
  lint(filePath: string): Promise<Result<LspDiagnostic[]>>;
  hover(filePath: string, pos: LspPosition): Promise<Result<LspHover | null>>;
  complete(
    filePath: string,
    pos: LspPosition,
  ): Promise<Result<LspCompletionItem[]>>;
  version(): Promise<Result<string>>;
}

export async function whichBinary(binary: string): Promise<boolean> {
  try {
    const cmd = new Deno.Command(binary, {
      args: ["--version"],
      stdout: "null",
      stderr: "null",
    });
    const { code } = await cmd.output();
    return code === 0;
  } catch {
    return false;
  }
}

export async function runChecker(
  binary: string,
  args: string[],
  opts: { cwd?: string; timeoutMs?: number } = {},
): Promise<Result<{ stdout: string; stderr: string; code: number }>> {
  try {
    const cmd = new Deno.Command(binary, {
      args,
      cwd: opts.cwd,
      stdout: "piped",
      stderr: "piped",
    });
    const proc = cmd.spawn();
    const timeout = opts.timeoutMs ?? 30_000;
    const timer = setTimeout(() => {
      try {
        proc.kill("SIGTERM");
      } catch { /* already exited */ }
    }, timeout);
    const out = await proc.output();
    clearTimeout(timer);
    return {
      ok: true,
      value: {
        stdout: new TextDecoder().decode(out.stdout),
        stderr: new TextDecoder().decode(out.stderr),
        code: out.code,
      },
    };
  } catch (e) {
    return { ok: false, error: `${binary} not available: ${String(e)}` };
  }
}

export function filePathFromUri(uri: string): string {
  if (uri.startsWith("file://")) return decodeURIComponent(uri.slice(7));
  return uri;
}

export function diagnosticAtLine(
  message: string,
  severity: 1 | 2 | 3 | 4,
  source: string,
  line = 0,
): LspDiagnostic {
  return {
    range: {
      start: { line, character: 0 },
      end: { line, character: 200 },
    },
    severity,
    source,
    message: message.trim(),
  };
}
