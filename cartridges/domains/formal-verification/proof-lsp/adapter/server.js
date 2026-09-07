// SPDX-License-Identifier: MPL-2.0
import { Readable, Writable } from "node:stream";
import { buildBackends } from "./backends/registry.js";
import { handleInitialize } from "./handlers/initialize.js";
import { handleDiagnostic } from "./handlers/diagnostic.js";
import { handleHover } from "./handlers/hover.js";
import { handleCompletion } from "./handlers/completion.js";
import { handleExecuteCommand } from "./handlers/executeCommand.js";
const HEADER_TERMINATOR = `\r
\r
`;
export function defaultOpts() {
  return { backends: buildBackends() };
}
export async function dispatch(message, opts) {
  const isRequest = (m) => typeof m.id < "u";
  try {
    switch (message.method) {
      case "initialize": {
        const result = await handleInitialize(message.params ?? {}, opts.backends);
        return isRequest(message) ? { jsonrpc: "2.0", id: message.id, result } : null;
      }
      case "textDocument/diagnostic": {
        const result = await handleDiagnostic(message.params ?? {}, opts.backends);
        return isRequest(message) ? { jsonrpc: "2.0", id: message.id, result } : null;
      }
      case "textDocument/hover": {
        const result = await handleHover(message.params ?? {}, opts.backends);
        return isRequest(message) ? { jsonrpc: "2.0", id: message.id, result } : null;
      }
      case "textDocument/completion": {
        const result = await handleCompletion(message.params ?? {}, opts.backends);
        return isRequest(message) ? { jsonrpc: "2.0", id: message.id, result } : null;
      }
      case "workspace/executeCommand": {
        const result = await handleExecuteCommand(message.params ?? {}, opts.backends);
        return isRequest(message) ? { jsonrpc: "2.0", id: message.id, result } : null;
      }
      case "shutdown":
        return isRequest(message) ? { jsonrpc: "2.0", id: message.id, result: null } : null;
      case "exit":
        return null;
      case "initialized":
      case "textDocument/didOpen":
      case "textDocument/didChange":
      case "textDocument/didClose":
      case "textDocument/didSave":
        return null;
      default:
        return isRequest(message) ? {
          jsonrpc: "2.0",
          id: message.id,
          error: { code: -32601, message: `Method not found: ${message.method}` }
        } : null;
    }
  } catch (e) {
    return isRequest(message) ? {
      jsonrpc: "2.0",
      id: message.id,
      error: { code: -32603, message: `Internal error: ${String(e)}` }
    } : null;
  }
}
export function encodeFramed(payload) {
  const body = new TextEncoder().encode(JSON.stringify(payload)), header = new TextEncoder().encode(`Content-Length: ${body.byteLength}${HEADER_TERMINATOR}`), out = new Uint8Array(header.byteLength + body.byteLength);
  out.set(header, 0);
  out.set(body, header.byteLength);
  return out;
}

export class FrameDecoder {
  #buffer = new Uint8Array(0);
  push(chunk) {
    const next = new Uint8Array(this.#buffer.byteLength + chunk.byteLength);
    next.set(this.#buffer, 0);
    next.set(chunk, this.#buffer.byteLength);
    this.#buffer = next;
  }
  next() {
    const text = new TextDecoder().decode(this.#buffer), terminator = text.indexOf(HEADER_TERMINATOR);
    if (terminator === -1)
      return null;
    const headerText = text.slice(0, terminator), match = headerText.match(/Content-Length:\s*(\d+)/i);
    if (!match) {
      this.#buffer = this.#buffer.slice(terminator + HEADER_TERMINATOR.length);
      return null;
    }
    const length = parseInt(match[1], 10), headerBytes = new TextEncoder().encode(headerText + HEADER_TERMINATOR).byteLength;
    if (this.#buffer.byteLength < headerBytes + length)
      return null;
    const bodyBytes = this.#buffer.slice(headerBytes, headerBytes + length);
    this.#buffer = this.#buffer.slice(headerBytes + length);
    const body = new TextDecoder().decode(bodyBytes);
    return JSON.parse(body);
  }
}
export async function serveStdio() {
  const opts = defaultOpts(), decoder = new FrameDecoder, reader = Readable.toWeb(process.stdin).getReader(), writer = Writable.toWeb(process.stdout).getWriter();
  try {
    while (!0) {
      const { value, done } = await reader.read();
      if (done)
        break;
      decoder.push(value);
      while (!0) {
        const msg = decoder.next();
        if (!msg)
          break;
        const resp = await dispatch(msg, opts);
        if (resp)
          await writer.write(encodeFramed(resp));
        if (msg.method === "exit")
          return;
      }
    }
  } finally {
    try {
      reader.releaseLock();
    } catch {}
    try {
      await writer.close();
    } catch {}
  }
}
if (import.meta.main)
  await serveStdio();
