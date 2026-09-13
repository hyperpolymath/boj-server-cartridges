// SPDX-License-Identifier: MPL-2.0
// Compile actual root cartridge entrypoints with Bun's module resolver.
const entries = [];
for await (const path of new Bun.Glob("cartridges/**/mod.js").scan(".")) {
  if (!path.includes("/_source-archive/") && !path.includes("/node_modules/")) entries.push(path);
}
if (!entries.length) throw new Error("No cartridge entrypoints found");
for (const path of entries.sort()) {
  const result = await Bun.build({entrypoints: [path], target: "bun"});
  if (!result.success) throw new AggregateError(result.logs, `Cartridge entrypoint failed: ${path}`);
}
console.log(`${entries.length} root cartridge JavaScript entrypoints compile and resolve with Bun`);
