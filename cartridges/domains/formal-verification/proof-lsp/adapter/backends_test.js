// SPDX-License-Identifier: MPL-2.0
import { test } from "bun:test";
import { writeTextFile, makeTempDir, remove } from "../../../../lib/files.js";
import { ok as assert, deepStrictEqual as assertEquals } from "node:assert/strict";
import { buildBackends, detectByExtension } from "./backends/registry.js";
test("buildBackends populates all four backends", () => {
  const map = buildBackends();
  assertEquals(map.size, 4);
  assert(map.has("coq"));
  assert(map.has("lean"));
  assert(map.has("isabelle"));
  assert(map.has("agda"));
});
test("detectByExtension picks coq for .v", () => {
  const map = buildBackends(), b = detectByExtension(map, "file:///tmp/a.v");
  assertEquals(b?.id, "coq");
});
test("detectByExtension picks lean for .lean", () => {
  const map = buildBackends(), b = detectByExtension(map, "file:///tmp/a.lean");
  assertEquals(b?.id, "lean");
});
test("detectByExtension picks isabelle for .thy", () => {
  const map = buildBackends(), b = detectByExtension(map, "file:///tmp/a.thy");
  assertEquals(b?.id, "isabelle");
});
test("detectByExtension picks agda for .agda", () => {
  const map = buildBackends(), b = detectByExtension(map, "file:///tmp/a.agda");
  assertEquals(b?.id, "agda");
});
test("detectByExtension picks agda for .lagda", () => {
  const map = buildBackends(), b = detectByExtension(map, "file:///tmp/a.lagda");
  assertEquals(b?.id, "agda");
});
test("detectByExtension returns undefined for unknown extension", () => {
  const map = buildBackends(), b = detectByExtension(map, "file:///tmp/a.txt");
  assertEquals(b, void 0);
});
test("CoqBackend.detect returns false for empty temp dir", async () => {
  const map = buildBackends(), tmp = await makeTempDir();
  try {
    const r = await map.get("coq").detect(tmp);
    assert(r.ok);
    assertEquals(r.ok && r.value, !1);
  } finally {
    await remove(tmp, { recursive: !0 });
  }
});
test("CoqBackend.detect returns true when .v file present", async () => {
  const map = buildBackends(), tmp = await makeTempDir();
  try {
    await writeTextFile(`${tmp}/proof.v`, "Theorem t: True. trivial. Qed.");
    const r = await map.get("coq").detect(tmp);
    assert(r.ok);
    assertEquals(r.ok && r.value, !0);
  } finally {
    await remove(tmp, { recursive: !0 });
  }
});
test("CoqBackend.lint on non-.v uri returns empty", async () => {
  const r = await buildBackends().get("coq").lint("file:///tmp/README.md");
  assert(r.ok);
  assertEquals(r.ok && r.value, []);
});
test("CoqBackend.complete returns Coq tactic items", async () => {
  const r = await buildBackends().get("coq").complete("file:///tmp/a.v", {
    line: 0,
    character: 0
  });
  assert(r.ok);
  assert(r.ok && r.value.some((i) => i.label === "intros"));
});
test("LeanBackend.complete returns Lean tactic items", async () => {
  const r = await buildBackends().get("lean").complete("file:///tmp/a.lean", {
    line: 0,
    character: 0
  });
  assert(r.ok);
  assert(r.ok && r.value.some((i) => i.label === "rw"));
});
test("IsabelleBackend.lint returns info-severity placeholder diagnostic", async () => {
  const r = await buildBackends().get("isabelle").lint("file:///tmp/a.thy");
  assert(r.ok);
  if (r.ok) {
    assertEquals(r.value.length, 1);
    assertEquals(r.value[0].severity, 3);
  }
});
test("AgdaBackend.lint on non-.agda uri returns empty", async () => {
  const r = await buildBackends().get("agda").lint("file:///tmp/README.md");
  assert(r.ok);
  assertEquals(r.ok && r.value, []);
});
