// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)
//
// Port of polystack/poly-orchestrator-lsp/lib/orchestrator/executor.ex.
// Original module: PolyOrchestrator.Orchestrator.Executor.
//
// Phase-by-phase execution with parallel-group dispatch, retry, output
// propagation, and per-step status tracking.

import type {
  ComponentStep,
  ExecutionPlan,
  Phase,
  Result,
} from "./types.ts";
import { err, ok } from "./types.ts";
import type { LspClient } from "./lsp_client.ts";

export interface ExecuteOpts {
  client: LspClient;
  /** When true, do not invoke LSP — return the dispatch matrix only. */
  dryRun?: boolean;
  /** Retry attempts per component on transient failure (default 0). */
  retryCount?: number;
  /** Max parallelism within a single parallel group (default unlimited). */
  maxParallel?: number;
  /** Per-component timeout in milliseconds (advisory; passed to LSP). */
  timeoutMs?: number;
  /** Pre-existing outputs from prior phases (for resumed executions). */
  initialOutputs?: Record<string, Record<string, unknown>>;
}

export interface PhaseExecution {
  phase: number;
  steps: ComponentStep[];
  outputs: Record<string, Record<string, unknown>>;
  errors: Array<{ id: string; reason: string }>;
  dispatched: string[][];
}

export interface DryRunResult {
  phase: number;
  dispatched: string[][];
}

/**
 * Execute a single phase of an `ExecutionPlan`. Returns the per-step
 * statuses, captured outputs, and (on failure) error list. A failure in
 * one component of a parallel group does NOT cancel siblings mid-flight;
 * siblings run to completion and the failure is surfaced in `errors`.
 */
export async function executePhase(
  plan: ExecutionPlan,
  phaseIndex: number,
  opts: ExecuteOpts,
): Promise<Result<PhaseExecution>> {
  const phase = plan.phases[phaseIndex];
  if (!phase) return err(`Phase index out of range: ${phaseIndex}`);

  if (opts.dryRun) {
    return ok({
      phase: phase.phase,
      steps: phase.components.map((c) => ({ ...c, status: "pending" })),
      outputs: {},
      errors: [],
      dispatched: phase.parallel,
    });
  }

  const outputs: Record<string, Record<string, unknown>> = {
    ...(opts.initialOutputs ?? {}),
  };
  const errors: Array<{ id: string; reason: string }> = [];
  const stepIndex = new Map(
    phase.components.map((c, idx) => [c.id, idx] as const),
  );
  const steps: ComponentStep[] = phase.components.map((c) => ({ ...c }));

  for (const group of phase.parallel) {
    const limited = limitConcurrency(
      group,
      opts.maxParallel ?? group.length,
    );
    for (const slice of limited) {
      const promises = slice.map((id) =>
        runOne(id, steps, stepIndex, outputs, opts)
      );
      const results = await Promise.all(promises);
      for (const r of results) {
        if (!r.ok) errors.push({ id: r.id, reason: r.error ?? "unknown" });
      }
    }
  }

  return ok({
    phase: phase.phase,
    steps,
    outputs,
    errors,
    dispatched: phase.parallel,
  });
}

interface RunResult {
  id: string;
  ok: true | false;
  error?: string;
}

async function runOne(
  id: string,
  steps: ComponentStep[],
  stepIndex: Map<string, number>,
  outputs: Record<string, Record<string, unknown>>,
  opts: ExecuteOpts,
): Promise<RunResult> {
  const idx = stepIndex.get(id);
  if (idx === undefined) return { id, ok: false, error: "Unknown step id" };
  const step = steps[idx];
  const interpolated: ComponentStep = {
    ...step,
    config: interpolateConfig(step.config, outputs),
    status: "running",
  };
  steps[idx] = interpolated;

  const attempts = (opts.retryCount ?? 0) + 1;
  for (let attempt = 1; attempt <= attempts; attempt++) {
    const result = await opts.client.executeComponent(interpolated);
    if (result.ok) {
      const final: ComponentStep = {
        ...interpolated,
        outputs: result.value,
        status: "succeeded",
      };
      steps[idx] = final;
      outputs[id] = result.value;
      return { id, ok: true };
    }
    if (attempt === attempts) {
      const final: ComponentStep = { ...interpolated, status: "failed" };
      steps[idx] = final;
      return { id, ok: false, error: result.error };
    }
  }
  return { id, ok: false, error: "unreachable" };
}

/** Split a parallel group into slices each at most `max` wide. */
export function limitConcurrency<T>(items: T[], max: number): T[][] {
  if (max <= 0 || items.length <= max) return [items];
  const slices: T[][] = [];
  for (let i = 0; i < items.length; i += max) {
    slices.push(items.slice(i, i + max));
  }
  return slices;
}

/**
 * Substitute `${component-id.field}` references inside any string value.
 * Walks nested objects + arrays.
 */
export function interpolateConfig(
  config: Record<string, unknown>,
  outputs: Record<string, Record<string, unknown>>,
): Record<string, unknown> {
  return walk(config, outputs) as Record<string, unknown>;
}

function walk(
  value: unknown,
  outputs: Record<string, Record<string, unknown>>,
): unknown {
  if (typeof value === "string") {
    return value.replace(/\$\{([^.}]+)\.([^}]+)\}/g, (whole, id, field) => {
      const out = outputs[id];
      if (!out) return whole;
      const v = out[field];
      return v === undefined ? whole : String(v);
    });
  }
  if (Array.isArray(value)) return value.map((v) => walk(v, outputs));
  if (value && typeof value === "object") {
    const next: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      next[k] = walk(v, outputs);
    }
    return next;
  }
  return value;
}

/** Convenience: execute all phases. Used by the `stack_execute` higher tool. */
export async function executeAllPhases(
  plan: ExecutionPlan,
  opts: ExecuteOpts,
): Promise<Result<PhaseExecution[]>> {
  const completed: PhaseExecution[] = [];
  let outputs: Record<string, Record<string, unknown>> = {
    ...(opts.initialOutputs ?? {}),
  };
  for (let i = 0; i < plan.phases.length; i++) {
    const r = await executePhase(plan, i, { ...opts, initialOutputs: outputs });
    if (!r.ok) return err(r.error);
    completed.push(r.value);
    outputs = { ...outputs, ...r.value.outputs };
    if (r.value.errors.length > 0) {
      return ok(completed);
    }
  }
  return ok(completed);
}

/** Surface dispatch matrix without invoking any LSP. */
export function dispatchMatrix(plan: ExecutionPlan): DryRunResult[] {
  return plan.phases.map((p: Phase) => ({
    phase: p.phase,
    dispatched: p.parallel,
  }));
}
