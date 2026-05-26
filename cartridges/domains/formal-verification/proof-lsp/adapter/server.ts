// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

import { buildBackends } from "./backends/registry.ts";
import { handleInitialize } from "./handlers/initialize.ts";
import { handleDiagnostic } from "./handlers/diagnostic.ts";
import { handleHover } from "./handlers/hover.ts";
import { handleCompletion } from "./handlers/completion.ts";
import { handleExecuteCommand } from "./handlers/executeCommand.ts";
import type {
  JsonRpcMessage,
  JsonRpcRequest,
  JsonRpcResponse,
} from "./types.ts";

const HEADER_TERMINATOR = "\r\n\r\n";

export interface DispatchOpts {
  readonly backends: ReturnType<typeof buildBackends>;
}

export function defaultOpts(): DispatchOpts {
  return { backends: buildBackends() };
}

export async function dispatch(
  message: JsonRpcMessage,
  opts: DispatchOpts,
): Promise<JsonRpcResponse | null> {
  const isRequest = (m: JsonRpcMessage): m is JsonRpcRequest =>
    typeof (m as JsonRpcRequest).id !== "undefined";

  try {
    switch (message.method) {
      case "initialize": {
        const result = await handleInitialize(
          (message.params ?? {}) as Parameters<typeof handleInitialize>[0],
          opts.backends,
        );
        return isRequest(message)
          ? { jsonrpc: "2.0", id: message.id, result }
          : null;
      }
      case "textDocument/diagnostic": {
        const result = await handleDiagnostic(
          (message.params ?? {}) as Parameters<typeof handleDiagnostic>[0],
          opts.backends,
        );
        return isRequest(message)
          ? { jsonrpc: "2.0", id: message.id, result }
          : null;
      }
      case "textDocument/hover": {
        const result = await handleHover(
          (message.params ?? {}) as Parameters<typeof handleHover>[0],
          opts.backends,
        );
        return isRequest(message)
          ? { jsonrpc: "2.0", id: message.id, result }
          : null;
      }
      case "textDocument/completion": {
        const result = await handleCompletion(
          (message.params ?? {}) as Parameters<typeof handleCompletion>[0],
          opts.backends,
        );
        return isRequest(message)
          ? { jsonrpc: "2.0", id: message.id, result }
          : null;
      }
      case "workspace/executeCommand": {
        const result = await handleExecuteCommand(
          (message.params ?? {}) as Parameters<typeof handleExecuteCommand>[0],
          opts.backends,
        );
        return isRequest(message)
          ? { jsonrpc: "2.0", id: message.id, result }
          : null;
      }
      case "shutdown": {
        return isRequest(message)
          ? { jsonrpc: "2.0", id: message.id, result: null }
          : null;
      }
      case "exit": {
        return null;
      }
      case "initialized":
      case "textDocument/didOpen":
      case "textDocument/didChange":
      case "textDocument/didClose":
      case "textDocument/didSave": {
        return null;
      }
      default:
        return isRequest(message)
          ? {
            jsonrpc: "2.0",
            id: message.id,
            error: { code: -32601, message: `Method not found: ${message.method}` },
          }
          : null;
    }
  } catch (e) {
    return isRequest(message)
      ? {
        jsonrpc: "2.0",
        id: message.id,
        error: { code: -32603, message: `Internal error: ${String(e)}` },
      }
      : null;
  }
}

export function encodeFramed(payload: unknown): Uint8Array {
  const body = new TextEncoder().encode(JSON.stringify(payload));
  const header = new TextEncoder().encode(
    `Content-Length: ${body.byteLength}${HEADER_TERMINATOR}`,
  );
  const out = new Uint8Array(header.byteLength + body.byteLength);
  out.set(header, 0);
  out.set(body, header.byteLength);
  return out;
}

export class FrameDecoder {
  #buffer = new Uint8Array(0);

  push(chunk: Uint8Array): void {
    const next = new Uint8Array(this.#buffer.byteLength + chunk.byteLength);
    next.set(this.#buffer, 0);
    next.set(chunk, this.#buffer.byteLength);
    this.#buffer = next;
  }

  next(): JsonRpcMessage | null {
    const text = new TextDecoder().decode(this.#buffer);
    const terminator = text.indexOf(HEADER_TERMINATOR);
    if (terminator === -1) return null;
    const headerText = text.slice(0, terminator);
    const match = headerText.match(/Content-Length:\s*(\d+)/i);
    if (!match) {
      this.#buffer = this.#buffer.slice(terminator + HEADER_TERMINATOR.length);
      return null;
    }
    const length = parseInt(match[1]!, 10);
    const headerBytes = new TextEncoder().encode(headerText + HEADER_TERMINATOR).byteLength;
    if (this.#buffer.byteLength < headerBytes + length) return null;
    const bodyBytes = this.#buffer.slice(headerBytes, headerBytes + length);
    this.#buffer = this.#buffer.slice(headerBytes + length);
    const body = new TextDecoder().decode(bodyBytes);
    return JSON.parse(body) as JsonRpcMessage;
  }
}

export async function serveStdio(): Promise<void> {
  const opts = defaultOpts();
  const decoder = new FrameDecoder();
  const reader = Deno.stdin.readable.getReader();
  const writer = Deno.stdout.writable.getWriter();

  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      decoder.push(value);
      while (true) {
        const msg = decoder.next();
        if (!msg) break;
        const resp = await dispatch(msg, opts);
        if (resp) await writer.write(encodeFramed(resp));
        if (msg.method === "exit") return;
      }
    }
  } finally {
    try {
      reader.releaseLock();
    } catch { /* ignore */ }
    try {
      await writer.close();
    } catch { /* ignore */ }
  }
}

if (import.meta.main) {
  await serveStdio();
}
