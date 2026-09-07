// SPDX-License-Identifier: MPL-2.0
import { err, ok } from "./types.js";
export async function executePhase(plan, phaseIndex, opts) {
  const phase = plan.phases[phaseIndex];
  if (!phase)
    return err(`Phase index out of range: ${phaseIndex}`);
  if (opts.dryRun)
    return ok({
      phase: phase.phase,
      steps: phase.components.map((c) => ({ ...c, status: "pending" })),
      outputs: {},
      errors: [],
      dispatched: phase.parallel
    });
  const outputs = {
    ...opts.initialOutputs ?? {}
  }, errors = [], stepIndex = new Map(phase.components.map((c, idx) => [c.id, idx])), steps = phase.components.map((c) => ({ ...c }));
  for (const group of phase.parallel) {
    const limited = limitConcurrency(group, opts.maxParallel ?? group.length);
    for (const slice of limited) {
      const promises = slice.map((id) => runOne(id, steps, stepIndex, outputs, opts)), results = await Promise.all(promises);
      for (const r of results)
        if (!r.ok)
          errors.push({ id: r.id, reason: r.error ?? "unknown" });
    }
  }
  return ok({
    phase: phase.phase,
    steps,
    outputs,
    errors,
    dispatched: phase.parallel
  });
}
async function runOne(id, steps, stepIndex, outputs, opts) {
  const idx = stepIndex.get(id);
  if (idx === void 0)
    return { id, ok: !1, error: "Unknown step id" };
  const step = steps[idx], interpolated = {
    ...step,
    config: interpolateConfig(step.config, outputs),
    status: "running"
  };
  steps[idx] = interpolated;
  const attempts = (opts.retryCount ?? 0) + 1;
  for (let attempt = 1;attempt <= attempts; attempt++) {
    const result = await opts.client.executeComponent(interpolated);
    if (result.ok) {
      const final = {
        ...interpolated,
        outputs: result.value,
        status: "succeeded"
      };
      steps[idx] = final;
      outputs[id] = result.value;
      return { id, ok: !0 };
    }
    if (attempt === attempts) {
      const final = { ...interpolated, status: "failed" };
      steps[idx] = final;
      return { id, ok: !1, error: result.error };
    }
  }
  return { id, ok: !1, error: "unreachable" };
}
export function limitConcurrency(items, max) {
  if (max <= 0 || items.length <= max)
    return [items];
  const slices = [];
  for (let i = 0;i < items.length; i += max)
    slices.push(items.slice(i, i + max));
  return slices;
}
export function interpolateConfig(config, outputs) {
  return walk(config, outputs);
}
function walk(value, outputs) {
  if (typeof value === "string")
    return value.replace(/\$\{([^.}]+)\.([^}]+)\}/g, (whole, id, field) => {
      const out = outputs[id];
      if (!out)
        return whole;
      const v = out[field];
      return v === void 0 ? whole : String(v);
    });
  if (Array.isArray(value))
    return value.map((v) => walk(v, outputs));
  if (value && typeof value === "object") {
    const next = {};
    for (const [k, v] of Object.entries(value))
      next[k] = walk(v, outputs);
    return next;
  }
  return value;
}
export async function executeAllPhases(plan, opts) {
  const completed = [];
  let outputs = {
    ...opts.initialOutputs ?? {}
  };
  for (let i = 0;i < plan.phases.length; i++) {
    const r = await executePhase(plan, i, { ...opts, initialOutputs: outputs });
    if (!r.ok)
      return err(r.error);
    completed.push(r.value);
    outputs = { ...outputs, ...r.value.outputs };
    if (r.value.errors.length > 0)
      return ok(completed);
  }
  return ok(completed);
}
export function dispatchMatrix(plan) {
  return plan.phases.map((p) => ({
    phase: p.phase,
    dispatched: p.parallel
  }));
}
