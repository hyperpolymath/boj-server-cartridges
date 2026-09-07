// SPDX-License-Identifier: MPL-2.0
import { detectByExtension } from "../backends/registry.js";
export async function handleCompletion(params, backends) {
  const uri = params.textDocument?.uri ?? "", backend = (params.backend ? backends.get(params.backend) : void 0) ?? detectByExtension(backends, uri);
  if (!backend)
    return { isIncomplete: !1, items: [] };
  const r = await backend.complete(uri, params.position);
  if (!r.ok)
    return { isIncomplete: !1, items: [] };
  return { isIncomplete: !1, items: r.value };
}
