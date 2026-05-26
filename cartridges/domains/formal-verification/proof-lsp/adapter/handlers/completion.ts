// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

import type { Backend } from "../backends/base.ts";
import { detectByExtension } from "../backends/registry.ts";
import type {
  BackendId,
  LspCompletionItem,
  LspPosition,
} from "../types.ts";

export interface CompletionParams {
  textDocument: { uri: string };
  position: LspPosition;
  backend?: BackendId;
}

export interface CompletionList {
  isIncomplete: boolean;
  items: LspCompletionItem[];
}

export async function handleCompletion(
  params: CompletionParams,
  backends: Map<BackendId, Backend>,
): Promise<CompletionList> {
  const uri = params.textDocument?.uri ?? "";
  const explicit = params.backend ? backends.get(params.backend) : undefined;
  const backend = explicit ?? detectByExtension(backends, uri);
  if (!backend) return { isIncomplete: false, items: [] };
  const r = await backend.complete(uri, params.position);
  if (!r.ok) return { isIncomplete: false, items: [] };
  return { isIncomplete: false, items: r.value };
}
