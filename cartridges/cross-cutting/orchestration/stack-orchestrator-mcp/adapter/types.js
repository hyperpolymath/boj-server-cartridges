// SPDX-License-Identifier: MPL-2.0
export function ok(value) {
  return { ok: !0, value };
}
export function err(error) {
  return { ok: !1, error };
}
