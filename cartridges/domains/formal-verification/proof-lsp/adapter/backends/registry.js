// SPDX-License-Identifier: MPL-2.0
import { CoqBackend } from "./coq.js";
import { LeanBackend } from "./lean.js";
import { IsabelleBackend } from "./isabelle.js";
import { AgdaBackend } from "./agda.js";
export function buildBackends() {
  const map = new Map;
  for (const backend of [
    new CoqBackend,
    new LeanBackend,
    new IsabelleBackend,
    new AgdaBackend
  ])
    map.set(backend.id, backend);
  return map;
}
export function detectByExtension(backends, uri) {
  const lower = uri.toLowerCase();
  for (const backend of backends.values())
    if (backend.extensions.some((ext) => lower.endsWith(ext)))
      return backend;
  return;
}
