// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)
//
// Port of polystack/poly-orchestrator-lsp/lib/orchestrator/lsp_client.ex.
// Speaks JSON-RPC 2.0 over child-process stdio to target LSP cartridges.
//
// Persistence: this port is in-memory only. The Elixir original wrote to
// VerisimDB; an equivalent Deno-side store is deferred (see
// docs/handover/2026-05-26/prompts/cartridge-02-phase-3-execute-rollback.adoc#pitfalls).

import type { ComponentStep, Result } from "./types.ts";
import { err, ok } from "./types.ts";

export interface LspClient {
  executeComponent(
    c: ComponentStep,
  ): Promise<Result<Record<string, unknown>>>;
  rollbackComponent(c: ComponentStep): Promise<Result<true>>;
  close(): Promise<void>;
}

export interface MockResponse {
  ok: boolean;
  outputs?: Record<string, unknown>;
  error?: string;
}

/** Test-only mock client. Records calls + returns canned responses. */
export class MockLspClient implements LspClient {
  readonly calls: Array<{ method: "execute" | "rollback"; id: string }> = [];
  readonly responses = new Map<string, MockResponse>();
  failOnce = new Set<string>();

  setResponse(componentId: string, response: MockResponse): void {
    this.responses.set(componentId, response);
  }

  setFailOnce(componentId: string): void {
    this.failOnce.add(componentId);
  }

  executeComponent(
    c: ComponentStep,
  ): Promise<Result<Record<string, unknown>>> {
    this.calls.push({ method: "execute", id: c.id });
    if (this.failOnce.has(c.id)) {
      this.failOnce.delete(c.id);
      return Promise.resolve(err(`transient failure on ${c.id}`));
    }
    const r = this.responses.get(c.id);
    if (!r) {
      return Promise.resolve(ok({ default: `output-of-${c.id}` }));
    }
    if (r.ok) return Promise.resolve(ok(r.outputs ?? {}));
    return Promise.resolve(err(r.error ?? "mock failure"));
  }

  rollbackComponent(c: ComponentStep): Promise<Result<true>> {
    this.calls.push({ method: "rollback", id: c.id });
    return Promise.resolve(ok(true));
  }

  close(): Promise<void> {
    return Promise.resolve();
  }
}

interface ConnectionEntry {
  proc: Deno.ChildProcess;
  writer: WritableStreamDefaultWriter<Uint8Array>;
  reader: ReadableStreamDefaultReader<Uint8Array>;
  buffer: Uint8Array;
}

/**
 * Production client. Spawns one Deno subprocess per `lsp_server` cartridge,
 * speaks LSP-framed JSON-RPC, dispatches `workspace/executeCommand`.
 * Connections are lazy + reused; closed via close().
 */
export class StdioLspClient implements LspClient {
  #conns = new Map<string, ConnectionEntry>();
  #nextId = 1;
  readonly cartridgesRoot: string;
  readonly timeoutMs: number;

  constructor(opts: { cartridgesRoot: string; timeoutMs?: number }) {
    this.cartridgesRoot = opts.cartridgesRoot;
    this.timeoutMs = opts.timeoutMs ?? 300_000;
  }

  async executeComponent(
    c: ComponentStep,
  ): Promise<Result<Record<string, unknown>>> {
    const connResult = await this.#ensureConnection(c.lsp_server);
    if (!connResult.ok) return connResult;
    return this.#sendCommand(connResult.value, "execute_component", {
      id: c.id,
      type: c.type,
      config: c.config,
    });
  }

  async rollbackComponent(c: ComponentStep): Promise<Result<true>> {
    const connResult = await this.#ensureConnection(c.lsp_server);
    if (!connResult.ok) return connResult;
    const r = await this.#sendCommand(connResult.value, "rollback_component", {
      id: c.id,
      type: c.type,
    });
    return r.ok ? ok(true) : err(r.error);
  }

  async close(): Promise<void> {
    for (const conn of this.#conns.values()) {
      try {
        await conn.writer.close();
      } catch { /* ignore */ }
      try {
        conn.reader.releaseLock();
      } catch { /* ignore */ }
      try {
        await conn.proc.stdout.cancel();
      } catch { /* ignore */ }
      try {
        await conn.proc.stderr.cancel();
      } catch { /* ignore */ }
      try {
        conn.proc.kill("SIGTERM");
      } catch { /* ignore */ }
      try {
        await conn.proc.status;
      } catch { /* ignore */ }
    }
    this.#conns.clear();
  }

  async #ensureConnection(lspServer: string): Promise<Result<ConnectionEntry>> {
    const existing = this.#conns.get(lspServer);
    if (existing) return ok(existing);

    const entry = `${this.cartridgesRoot}/${lspServerToPath(lspServer)}/adapter/server.ts`;
    try {
      const proc = new Deno.Command(Deno.execPath(), {
        args: ["run", "--allow-read", "--allow-run", "--allow-env", entry],
        stdin: "piped",
        stdout: "piped",
        stderr: "piped",
      }).spawn();
      const conn: ConnectionEntry = {
        proc,
        writer: proc.stdin.getWriter(),
        reader: proc.stdout.getReader(),
        buffer: new Uint8Array(0),
      };
      this.#conns.set(lspServer, conn);
      return ok(conn);
    } catch (e) {
      return err(`Failed to spawn LSP ${lspServer}: ${String(e)}`);
    }
  }

  async #sendCommand(
    conn: ConnectionEntry,
    command: string,
    args: Record<string, unknown>,
  ): Promise<Result<Record<string, unknown>>> {
    const id = this.#nextId++;
    const req = {
      jsonrpc: "2.0",
      id,
      method: "workspace/executeCommand",
      params: { command, arguments: [args] },
    };
    const body = new TextEncoder().encode(JSON.stringify(req));
    const header = new TextEncoder().encode(
      `Content-Length: ${body.byteLength}\r\n\r\n`,
    );
    const framed = new Uint8Array(header.byteLength + body.byteLength);
    framed.set(header, 0);
    framed.set(body, header.byteLength);
    try {
      await conn.writer.write(framed);
    } catch (e) {
      return err(`Write to LSP failed: ${String(e)}`);
    }
    const deadline = Date.now() + this.timeoutMs;
    while (Date.now() < deadline) {
      const msg = decodeOne(conn);
      if (msg) {
        if ("error" in msg && msg.error) {
          return err((msg.error as { message: string }).message ?? "LSP error");
        }
        return ok((msg.result ?? {}) as Record<string, unknown>);
      }
      try {
        const { value, done } = await conn.reader.read();
        if (done) return err("LSP closed stdout");
        const merged = new Uint8Array(conn.buffer.byteLength + value.byteLength);
        merged.set(conn.buffer, 0);
        merged.set(value, conn.buffer.byteLength);
        conn.buffer = merged;
      } catch (e) {
        return err(`Read from LSP failed: ${String(e)}`);
      }
    }
    return err(`LSP request timed out after ${this.timeoutMs}ms`);
  }
}

interface JsonRpcResponseLike {
  result?: unknown;
  error?: { code: number; message: string };
}

function decodeOne(conn: ConnectionEntry): JsonRpcResponseLike | null {
  const text = new TextDecoder().decode(conn.buffer);
  const terminator = text.indexOf("\r\n\r\n");
  if (terminator === -1) return null;
  const match = text.slice(0, terminator).match(/Content-Length:\s*(\d+)/i);
  if (!match) {
    conn.buffer = conn.buffer.slice(terminator + 4);
    return null;
  }
  const length = parseInt(match[1]!, 10);
  const headerBytes =
    new TextEncoder().encode(text.slice(0, terminator) + "\r\n\r\n").byteLength;
  if (conn.buffer.byteLength < headerBytes + length) return null;
  const bodyBytes = conn.buffer.slice(headerBytes, headerBytes + length);
  conn.buffer = conn.buffer.slice(headerBytes + length);
  return JSON.parse(new TextDecoder().decode(bodyBytes));
}

/**
 * Map an lsp_server identifier from a stack file to a cartridge subpath.
 * Tries both the exact form ("proof-lsp") and the polystack-style
 * legacy form ("poly-proof").
 */
export function lspServerToPath(lspServer: string): string {
  const direct: Record<string, string> = {
    "proof-lsp": "domains/formal-verification/proof-lsp",
    "cloud-lsp": "domains/cloud/cloud-lsp",
    "container-lsp": "domains/container/container-lsp",
    "database-lsp": "domains/database/database-lsp",
    "k8s-lsp": "domains/container/k8s-lsp",
    "git-lsp": "domains/development/git-lsp",
    "iac-lsp": "domains/infrastructure/iac-lsp",
    "observe-lsp": "domains/observability/observe-lsp",
    "queues-lsp": "domains/messaging/queues-lsp",
    "secrets-lsp": "domains/security/secrets-lsp",
    "ssg-lsp": "domains/web/ssg-lsp",
  };
  if (direct[lspServer]) return direct[lspServer];
  const legacy: Record<string, string> = {
    "poly-proof": "domains/formal-verification/proof-lsp",
    "poly-cloud": "domains/cloud/cloud-lsp",
    "poly-container": "domains/container/container-lsp",
    "poly-db": "domains/database/database-lsp",
    "poly-k8s": "domains/container/k8s-lsp",
    "poly-git": "domains/development/git-lsp",
    "poly-iac": "domains/infrastructure/iac-lsp",
    "poly-observability": "domains/observability/observe-lsp",
    "poly-queue": "domains/messaging/queues-lsp",
    "poly-secret": "domains/security/secrets-lsp",
    "poly-ssg": "domains/web/ssg-lsp",
  };
  return legacy[lspServer] ?? lspServer;
}
