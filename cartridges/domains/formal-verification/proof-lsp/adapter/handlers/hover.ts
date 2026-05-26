// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

import type { Backend } from "../backends/base.ts";
import { detectByExtension } from "../backends/registry.ts";
import type { BackendId, LspHover, LspPosition } from "../types.ts";

export interface HoverParams {
  textDocument: { uri: string };
  position: LspPosition;
  backend?: BackendId;
}

export async function handleHover(
  params: HoverParams,
  backends: Map<BackendId, Backend>,
): Promise<LspHover | null> {
  const uri = params.textDocument?.uri ?? "";
  const explicit = params.backend ? backends.get(params.backend) : undefined;
  const backend = explicit ?? detectByExtension(backends, uri);
  if (!backend) return null;
  const r = await backend.hover(uri, params.position);
  return r.ok ? r.value : null;
}
