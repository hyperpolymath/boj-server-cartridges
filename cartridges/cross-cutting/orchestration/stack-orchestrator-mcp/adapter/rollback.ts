// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)
//
// Rollback driver — reverse-executes a partially-executed plan.
// Consumes the rollback plan produced by planner.ts buildRollbackPlan().

import type { ComponentStep, ExecutionPlan, Result } from "./types.ts";
import { err, ok } from "./types.ts";
import type { LspClient } from "./lsp_client.ts";
import { buildRollbackPlan } from "./planner.ts";

export interface RollbackOpts {
  client: LspClient;
  /** Stop rollback once we've reverted up to (and including) this phase index. */
  toPhase?: number;
  /** Only rollback steps that successfully ran. */
  executedSteps?: ComponentStep[];
}

export interface RollbackResult {
  phasesReverted: number[];
  rolledBack: string[];
  errors: Array<{ id: string; reason: string }>;
}

/**
 * Roll back an executed (or partially-executed) plan. Walks phases in
 * reverse order and asks the LSP client to undo each component.
 * Components that never ran successfully are skipped.
 */
export async function rollback(
  plan: ExecutionPlan,
  opts: RollbackOpts,
): Promise<Result<RollbackResult>> {
  if (plan.rollback_strategy.enabled === false) {
    return err("Rollback disabled by stack.rollback.enabled = false");
  }

  const rollbackPlan = buildRollbackPlan(plan);
  const executedIds = new Set(
    (opts.executedSteps ?? [])
      .filter((s) => s.status === "succeeded")
      .map((s) => s.id),
  );
  const targetPhase = opts.toPhase ?? -1;

  const result: RollbackResult = {
    phasesReverted: [],
    rolledBack: [],
    errors: [],
  };

  // rollbackPlan.phases is in reverse order of forward execution.
  // phase.phase is negative (e.g. -2, -1) — its absolute value is the
  // forward phase number. `toPhase` is the forward index to roll back to.
  for (const phase of rollbackPlan.phases) {
    const forwardPhase = -phase.phase;
    if (targetPhase >= 0 && forwardPhase < targetPhase) break;

    const candidates = phase.components.filter((c) =>
      executedIds.size === 0 || executedIds.has(c.id)
    );
    const promises = candidates.map(async (step) => {
      const r = await opts.client.rollbackComponent(step);
      if (!r.ok) return { id: step.id, ok: false as const, error: r.error };
      return { id: step.id, ok: true as const };
    });
    const groupResults = await Promise.all(promises);
    for (const gr of groupResults) {
      if (gr.ok) {
        result.rolledBack.push(gr.id);
      } else {
        result.errors.push({ id: gr.id, reason: gr.error ?? "unknown" });
      }
    }
    result.phasesReverted.push(forwardPhase);
  }

  return ok(result);
}
