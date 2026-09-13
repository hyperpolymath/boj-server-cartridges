// SPDX-License-Identifier: MPL-2.0
import { Command } from "../../../../lib/process.js";
import { err, ok } from "./types.js";

export class MockLspClient {
  calls = [];
  responses = new Map;
  failOnce = new Set;
  setResponse(componentId, response) {
    this.responses.set(componentId, response);
  }
  setFailOnce(componentId) {
    this.failOnce.add(componentId);
  }
  executeComponent(c) {
    this.calls.push({ method: "execute", id: c.id });
    if (this.failOnce.has(c.id)) {
      this.failOnce.delete(c.id);
      return Promise.resolve(err(`transient failure on ${c.id}`));
    }
    const r = this.responses.get(c.id);
    if (!r)
      return Promise.resolve(ok({ default: `output-of-${c.id}` }));
    if (r.ok)
      return Promise.resolve(ok(r.outputs ?? {}));
    return Promise.resolve(err(r.error ?? "mock failure"));
  }
  rollbackComponent(c) {
    this.calls.push({ method: "rollback", id: c.id });
    return Promise.resolve(ok(!0));
  }
  close() {
    return Promise.resolve();
  }
}

export class StdioLspClient {
  #conns = new Map;
  #nextId = 1;
  cartridgesRoot;
  timeoutMs;
  constructor(opts) {
    this.cartridgesRoot = opts.cartridgesRoot;
    this.timeoutMs = opts.timeoutMs ?? 300000;
  }
  async executeComponent(c) {
    const connResult = await this.#ensureConnection(c.lsp_server);
    if (!connResult.ok)
      return connResult;
    return this.#sendCommand(connResult.value, "execute_component", {
      id: c.id,
      type: c.type,
      config: c.config
    });
  }
  async rollbackComponent(c) {
    const connResult = await this.#ensureConnection(c.lsp_server);
    if (!connResult.ok)
      return connResult;
    const r = await this.#sendCommand(connResult.value, "rollback_component", {
      id: c.id,
      type: c.type
    });
    return r.ok ? ok(!0) : err(r.error);
  }
  async close() {
    for (const conn of this.#conns.values()) {
      try {
        await conn.writer.close();
      } catch {}
      try {
        conn.reader.releaseLock();
      } catch {}
      try {
        await conn.proc.stdout.cancel();
      } catch {}
      try {
        await conn.proc.stderr.cancel();
      } catch {}
      try {
        conn.proc.kill("SIGKILL");
      } catch {}
      try {
        await conn.proc.status;
      } catch {}
    }
    this.#conns.clear();
  }
  async#ensureConnection(lspServer) {
    const existing = this.#conns.get(lspServer);
    if (existing && !existing.dead)
      return ok(existing);
    if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(lspServer)) return err("invalid LSP server name");
    const entry = `${this.cartridgesRoot}/${lspServerToPath(lspServer)}/adapter/server.js`;
    try {
      const proc = new Command(process.execPath, {
        args: ["run", entry],
        stdin: "piped",
        stdout: "piped",
        stderr: "null"
      }).spawn(), conn = {
        proc,
        writer: proc.stdin.getWriter(),
        reader: proc.stdout.getReader(),
        buffer: new Uint8Array(0),
        queue: Promise.resolve(),
        dead: false
      };
      this.#conns.set(lspServer, conn);
      return ok(conn);
    } catch (e) {
      return err(`Failed to spawn LSP ${lspServer}: ${String(e)}`);
    }
  }
  async#sendCommand(conn, command, args) {
    const next = conn.queue.then(() => this.#exchange(conn, command, args));
    conn.queue = next.catch(() => {});
    return next;
  }
  async#exchange(conn, command, args) {
    let timer;
    try {
      return await Promise.race([this.#exchangeInner(conn, command, args), new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error("LSP deadline exceeded; outcome unknown")), this.timeoutMs);
      })]);
    } catch (error) {
      conn.dead = true;
      try { conn.proc.kill("SIGKILL"); } catch {}
      return err(`LSP exchange failed; outcome unknown: ${String(error)}`);
    } finally { clearTimeout(timer); }
  }
  async#exchangeInner(conn, command, args) {
    if (conn.dead) return err("LSP connection closed; outcome unknown");
    const req = {
      jsonrpc: "2.0",
      id: this.#nextId++,
      method: "workspace/executeCommand",
      params: { command, arguments: [args] }
    }, body = new TextEncoder().encode(JSON.stringify(req)), header = new TextEncoder().encode(`Content-Length: ${body.byteLength}\r
\r
`), framed = new Uint8Array(header.byteLength + body.byteLength);
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
        if (msg.id !== req.id) continue;
        if (msg.result?.ok === false) return err(msg.result.error ?? "LSP command failed");
        if ("error" in msg && msg.error)
          return err(msg.error.message ?? "LSP error");
        return ok(msg.result ?? {});
      }
      try {
        let timer;
        let part;
        try {
          part = await Promise.race([conn.reader.read(), new Promise((_, reject) => {
            timer = setTimeout(() => reject(new Error("LSP deadline exceeded; outcome unknown")), Math.max(1, deadline - Date.now()));
          })]);
        } finally { clearTimeout(timer); }
        const { value, done } = part;
        if (done)
          return err("LSP closed stdout");
        if (conn.buffer.byteLength + value.byteLength > 1048576) throw new Error("LSP output limit exceeded; outcome unknown");
        const merged = new Uint8Array(conn.buffer.byteLength + value.byteLength);
        merged.set(conn.buffer, 0);
        merged.set(value, conn.buffer.byteLength);
        conn.buffer = merged;
      } catch (e) {
        conn.dead = true; conn.proc.kill("SIGKILL");
        return err(`Read from LSP failed: ${String(e)}`);
      }
    }
    conn.dead = true; conn.proc.kill("SIGKILL");
    return err(`LSP request timed out after ${this.timeoutMs}ms; outcome unknown`);
  }
}
function decodeOne(conn) {
  const text = new TextDecoder().decode(conn.buffer), terminator = text.indexOf(`\r
\r
`);
  if (terminator === -1)
    return null;
  const match = text.slice(0, terminator).match(/Content-Length:\s*(\d+)/i);
  if (!match) throw new Error("Missing LSP Content-Length");
  const length = parseInt(match[1], 10), headerBytes = new TextEncoder().encode(text.slice(0, terminator) + `\r
\r
`).byteLength;
  if (!Number.isSafeInteger(length) || length > 1048576) throw new Error("LSP frame exceeds output limit");
  if (conn.buffer.byteLength < headerBytes + length)
    return null;
  const bodyBytes = conn.buffer.slice(headerBytes, headerBytes + length);
  conn.buffer = conn.buffer.slice(headerBytes + length);
  return JSON.parse(new TextDecoder().decode(bodyBytes));
}
export function lspServerToPath(lspServer) {
  const direct = {
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
    "ssg-lsp": "domains/web/ssg-lsp"
  };
  if (direct[lspServer])
    return direct[lspServer];
  return {
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
    "poly-ssg": "domains/web/ssg-lsp"
  }[lspServer] ?? lspServer;
}
