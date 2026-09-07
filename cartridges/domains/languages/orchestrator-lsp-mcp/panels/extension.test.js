// SPDX-License-Identifier: MPL-2.0
import { mock, test, expect } from "bun:test";
const logs = [];
let instance;
mock.module("vscode", () => ({
  workspace: {workspaceFolders: [], getConfiguration: () => ({get: (key) => key === "adapterDir" ? "/test/adapter" : undefined})},
  window: {createOutputChannel: () => ({appendLine: (s) => logs.push(s), dispose() {}}), showErrorMessage: (s) => logs.push(s)}
}));
mock.module("vscode-languageclient/node", () => ({
  LanguageClient: class {
    constructor(id, name, server, client) { instance = this; Object.assign(this, {id, name, server, client, stopped: false}); }
    async start() {}
    async stop() { this.stopped = true; }
    dispose() {}
  }
}));
const { activate, deactivate } = require("./lib/js/src/Extension.js");
test("compiled extension starts the configured adapter and registers cleanup", async () => {
  const context = {subscriptions: []};
  activate(context);
  await Promise.resolve();
  expect(instance.server.run.command).toBe("mix");
  expect(instance.server.run.options.cwd).toBe("/test/adapter");
  expect(context.subscriptions.length).toBe(2);
  expect(logs.some((s) => s.includes("connected to 12"))).toBe(false);
  await deactivate();
  expect(instance.stopped).toBe(true);
});
