// SPDX-License-Identifier: MPL-2.0
import { err, ok } from "./types.js";
import { buildRollbackPlan } from "./planner.js";
export async function rollback(plan, opts) {
  if (plan.rollback_strategy.enabled === !1)
    return err("Rollback disabled by stack.rollback.enabled = false");
  const rollbackPlan = buildRollbackPlan(plan), executedIds = new Set((opts.executedSteps ?? []).filter((s) => s.status === "succeeded").map((s) => s.id)), targetPhase = opts.toPhase ?? -1, result = {
    phasesReverted: [],
    rolledBack: [],
    errors: []
  };
  for (const phase of rollbackPlan.phases) {
    const forwardPhase = -phase.phase;
    if (targetPhase >= 0 && forwardPhase < targetPhase)
      break;
    const promises = phase.components.filter((c) => executedIds.size === 0 || executedIds.has(c.id)).map(async (step) => {
      const r = await opts.client.rollbackComponent(step);
      if (!r.ok)
        return { id: step.id, ok: !1, error: r.error };
      return { id: step.id, ok: !0 };
    }), groupResults = await Promise.all(promises);
    for (const gr of groupResults)
      if (gr.ok)
        result.rolledBack.push(gr.id);
      else
        result.errors.push({ id: gr.id, reason: gr.error ?? "unknown" });
    result.phasesReverted.push(forwardPhase);
  }
  return ok(result);
}
