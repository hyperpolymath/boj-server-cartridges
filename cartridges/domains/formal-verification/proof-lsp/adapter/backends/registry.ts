// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

import type { Backend } from "./base.ts";
import type { BackendId } from "../types.ts";
import { CoqBackend } from "./coq.ts";
import { LeanBackend } from "./lean.ts";
import { IsabelleBackend } from "./isabelle.ts";
import { AgdaBackend } from "./agda.ts";

export function buildBackends(): Map<BackendId, Backend> {
  const map = new Map<BackendId, Backend>();
  for (const backend of [
    new CoqBackend(),
    new LeanBackend(),
    new IsabelleBackend(),
    new AgdaBackend(),
  ]) {
    map.set(backend.id, backend);
  }
  return map;
}

export function detectByExtension(
  backends: Map<BackendId, Backend>,
  uri: string,
): Backend | undefined {
  const lower = uri.toLowerCase();
  for (const backend of backends.values()) {
    if (backend.extensions.some((ext) => lower.endsWith(ext))) return backend;
  }
  return undefined;
}
