// SPDX-License-Identifier: MPL-2.0
// Bun/Node process transport used by the LSP adapters. This is process
// separation, not filesystem or network confinement.
import { spawn } from "node:child_process";
import { Readable, Writable } from "node:stream";
export class Command {
  constructor(binary, options = {}) { this.binary = binary; this.options = options; }
  spawn() {
    const o = this.options;
    const stdio = [o.stdin, o.stdout, o.stderr].map((v) => v === "null" ? "ignore" : v === "inherit" ? "inherit" : "pipe");
    const child = spawn(this.binary, o.args ?? [], {cwd: o.cwd, env: o.env ?? process.env, stdio});
    const status = new Promise((resolve, reject) => {
      child.once("error", reject);
      child.once("close", (code, signal) => resolve({code: code ?? 128, success: code === 0, signal}));
    });
    // A consumer can attach after the spawn error; avoid an unhandled rejection.
    status.catch(() => {});
    const stdout = child.stdout ? Readable.toWeb(child.stdout) : new ReadableStream({start(c) { c.close(); }});
    const stderr = child.stderr ? Readable.toWeb(child.stderr) : new ReadableStream({start(c) { c.close(); }});
    return {
      stdin: child.stdin ? Writable.toWeb(child.stdin) : undefined,
      stdout, stderr, status,
      kill: (signal = "SIGTERM") => child.kill(signal),
      async output() {
        const read = async (stream) => {
          const chunks = []; let size = 0;
          for await (const chunk of stream) {
            size += chunk.length;
            if (size > 1048576) { child.kill("SIGKILL"); throw new Error("checker output limit exceeded"); }
            chunks.push(chunk);
          }
          return new Uint8Array(Buffer.concat(chunks));
        };
        const [out, err, result] = await Promise.all([read(stdout), read(stderr), status]);
        return {...result, stdout: out, stderr: err};
      }
    };
  }
  output() { return this.spawn().output(); }
}
