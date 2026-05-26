// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

import { assert, assertEquals } from "@std/assert";
import { buildBackends, detectByExtension } from "./backends/registry.ts";

Deno.test("buildBackends populates all four backends", () => {
  const map = buildBackends();
  assertEquals(map.size, 4);
  assert(map.has("coq"));
  assert(map.has("lean"));
  assert(map.has("isabelle"));
  assert(map.has("agda"));
});

Deno.test("detectByExtension picks coq for .v", () => {
  const map = buildBackends();
  const b = detectByExtension(map, "file:///tmp/a.v");
  assertEquals(b?.id, "coq");
});

Deno.test("detectByExtension picks lean for .lean", () => {
  const map = buildBackends();
  const b = detectByExtension(map, "file:///tmp/a.lean");
  assertEquals(b?.id, "lean");
});

Deno.test("detectByExtension picks isabelle for .thy", () => {
  const map = buildBackends();
  const b = detectByExtension(map, "file:///tmp/a.thy");
  assertEquals(b?.id, "isabelle");
});

Deno.test("detectByExtension picks agda for .agda", () => {
  const map = buildBackends();
  const b = detectByExtension(map, "file:///tmp/a.agda");
  assertEquals(b?.id, "agda");
});

Deno.test("detectByExtension picks agda for .lagda", () => {
  const map = buildBackends();
  const b = detectByExtension(map, "file:///tmp/a.lagda");
  assertEquals(b?.id, "agda");
});

Deno.test("detectByExtension returns undefined for unknown extension", () => {
  const map = buildBackends();
  const b = detectByExtension(map, "file:///tmp/a.txt");
  assertEquals(b, undefined);
});

Deno.test("CoqBackend.detect returns false for empty temp dir", async () => {
  const map = buildBackends();
  const tmp = await Deno.makeTempDir();
  try {
    const r = await map.get("coq")!.detect(tmp);
    assert(r.ok);
    assertEquals(r.ok && r.value, false);
  } finally {
    await Deno.remove(tmp, { recursive: true });
  }
});

Deno.test("CoqBackend.detect returns true when .v file present", async () => {
  const map = buildBackends();
  const tmp = await Deno.makeTempDir();
  try {
    await Deno.writeTextFile(`${tmp}/proof.v`, "Theorem t: True. trivial. Qed.");
    const r = await map.get("coq")!.detect(tmp);
    assert(r.ok);
    assertEquals(r.ok && r.value, true);
  } finally {
    await Deno.remove(tmp, { recursive: true });
  }
});

Deno.test("CoqBackend.lint on non-.v uri returns empty", async () => {
  const map = buildBackends();
  const r = await map.get("coq")!.lint("file:///tmp/README.md");
  assert(r.ok);
  assertEquals(r.ok && r.value, []);
});

Deno.test("CoqBackend.complete returns Coq tactic items", async () => {
  const map = buildBackends();
  const r = await map.get("coq")!.complete("file:///tmp/a.v", {
    line: 0,
    character: 0,
  });
  assert(r.ok);
  assert(r.ok && r.value.some((i) => i.label === "intros"));
});

Deno.test("LeanBackend.complete returns Lean tactic items", async () => {
  const map = buildBackends();
  const r = await map.get("lean")!.complete("file:///tmp/a.lean", {
    line: 0,
    character: 0,
  });
  assert(r.ok);
  assert(r.ok && r.value.some((i) => i.label === "rw"));
});

Deno.test("IsabelleBackend.lint returns info-severity placeholder diagnostic", async () => {
  const map = buildBackends();
  const r = await map.get("isabelle")!.lint("file:///tmp/a.thy");
  assert(r.ok);
  if (r.ok) {
    assertEquals(r.value.length, 1);
    assertEquals(r.value[0].severity, 3);
  }
});

Deno.test("AgdaBackend.lint on non-.agda uri returns empty", async () => {
  const map = buildBackends();
  const r = await map.get("agda")!.lint("file:///tmp/README.md");
  assert(r.ok);
  assertEquals(r.ok && r.value, []);
});
