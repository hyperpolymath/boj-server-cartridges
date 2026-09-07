// SPDX-License-Identifier: MPL-2.0
import { detectByExtension } from "../backends/registry.js";
export async function handleHover(params, backends) {
  const uri = params.textDocument?.uri ?? "", backend = (params.backend ? backends.get(params.backend) : void 0) ?? detectByExtension(backends, uri);
  if (!backend)
    return null;
  const r = await backend.hover(uri, params.position);
  return r.ok ? r.value : null;
}
