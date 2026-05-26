// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)
//
// Port of polystack/poly-orchestrator-lsp/lib/orchestrator/planner.ex.
// Original module: PolyOrchestrator.Orchestrator.Planner.
//
// Responsibilities:
// - Topological sort of dependency graph
// - Parallel execution grouping per phase
// - LSP server routing (carried through ComponentStep.lsp_server)
// - Rollback plan derivation
// - Duration estimation heuristic

import {
  extractDependencyGraph,
  extractSecurityPolicies,
  type DependencyGraph,
} from "./parser.ts";
import type {
  Component,
  ComponentStep,
  ExecutionPlan,
  Phase,
  RollbackStrategy,
  Stack,
  Result,
} from "./types.ts";
import { err, ok } from "./types.ts";

/** Build a complete execution plan from a parsed (and interpolated) stack. */
export function buildPlan(stack: Stack): Result<ExecutionPlan> {
  const graph = extractDependencyGraph(stack);

  const graphResult = validateGraph(graph);
  if (!graphResult.ok) return graphResult;

  const sortedResult = topologicalSort(graph);
  if (!sortedResult.ok) return sortedResult;

  const phasesResult = buildPhases(sortedResult.value, stack);
  if (!phasesResult.ok) return phasesResult;

  return ok({
    stack_id: stack.metadata.name,
    phases: phasesResult.value,
    security_policies: extractSecurityPolicies(stack),
    rollback_strategy: getRollbackStrategy(stack),
    verification: stack.verification ?? [],
  });
}

/**
 * Validate that the dependency graph is acyclic + has no dangling edges.
 * Returns a friendly error pointing at offending vertices.
 */
export function validateGraph(graph: DependencyGraph): Result<true> {
  // Check for edges referencing unknown vertices.
  for (const [from, to] of graph.edges) {
    if (!graph.vertices.has(from)) {
      return err(`Dependency edge references unknown component: ${from}`);
    }
    if (!graph.vertices.has(to)) {
      return err(`Dependency edge references unknown component: ${to}`);
    }
  }
  // Detect cycles via Kahn — if topo sort fails to consume all nodes,
  // a cycle exists.
  const cycle = findCycle(graph);
  if (cycle.length > 0) {
    return err(`Cyclic dependencies detected: ${cycle.join(" → ")}`);
  }
  return ok(true);
}

/**
 * Topological sort via Kahn's algorithm. Stable: when multiple nodes have
 * in-degree 0, the one with the lexicographically-smaller id wins.
 */
export function topologicalSort(graph: DependencyGraph): Result<string[]> {
  const inDegree = new Map<string, number>();
  const adjacency = new Map<string, string[]>();
  for (const id of graph.vertices.keys()) {
    inDegree.set(id, 0);
    adjacency.set(id, []);
  }
  for (const [from, to] of graph.edges) {
    inDegree.set(to, (inDegree.get(to) ?? 0) + 1);
    adjacency.get(from)!.push(to);
  }

  const ready: string[] = [];
  for (const [id, deg] of inDegree) if (deg === 0) ready.push(id);
  ready.sort();

  const sorted: string[] = [];
  while (ready.length > 0) {
    const id = ready.shift()!;
    sorted.push(id);
    for (const next of adjacency.get(id) ?? []) {
      const d = (inDegree.get(next) ?? 0) - 1;
      inDegree.set(next, d);
      if (d === 0) {
        // Maintain stable order.
        const insertAt = ready.findIndex((r) => r > next);
        if (insertAt === -1) ready.push(next);
        else ready.splice(insertAt, 0, next);
      }
    }
  }

  if (sorted.length !== graph.vertices.size) {
    return err("Cannot sort graph (cyclic dependencies)");
  }
  return ok(sorted);
}

/**
 * Build execution phases. Components are first grouped by their declared
 * `phase` field (default 1); within a phase, components with no
 * intra-phase dependencies are bundled into parallel groups.
 */
export function buildPhases(
  sortedIds: string[],
  stack: Stack,
): Result<Phase[]> {
  const components = stack.components ?? [];
  const componentMap = new Map(components.map((c) => [c.id, c]));

  // Walk sortedIds (already topo-sorted) and respect declared phases.
  const sortedComponents: Component[] = [];
  for (const id of sortedIds) {
    const c = componentMap.get(id);
    if (c) sortedComponents.push(c);
  }

  // Group by declared phase number.
  const phaseGroups = new Map<number, Component[]>();
  for (const c of sortedComponents) {
    const p = c.phase ?? 1;
    if (!phaseGroups.has(p)) phaseGroups.set(p, []);
    phaseGroups.get(p)!.push(c);
  }

  const phases: Phase[] = [];
  const phaseNumbers = [...phaseGroups.keys()].sort((a, b) => a - b);
  for (const phaseNum of phaseNumbers) {
    const comps = phaseGroups.get(phaseNum)!;
    phases.push({
      phase: phaseNum,
      parallel: identifyParallelComponents(comps),
      components: comps.map(buildComponentStep),
    });
  }

  return ok(phases);
}

/** Lift a Component into a ComponentStep (the runtime execution shape). */
export function buildComponentStep(component: Component): ComponentStep {
  return {
    id: component.id,
    type: component.type,
    lsp_server: component.lsp_server,
    config: component.config ?? {},
    depends_on: component.depends_on ?? [],
    outputs: {},
    status: "pending",
  };
}

/**
 * Within a single phase, identify which components can be launched in
 * parallel — i.e. they have no dependencies on other components also
 * inside this phase.
 *
 * Returns an array of parallel-groups (each group is a list of component
 * ids). Successive groups must run sequentially with respect to each
 * other; components within a group may run concurrently.
 */
export function identifyParallelComponents(
  components: Component[],
): string[][] {
  const phaseIds = new Set(components.map((c) => c.id));
  const completed = new Set<string>();
  const groups: string[][] = [];
  let remaining = [...components];

  while (remaining.length > 0) {
    const ready = remaining.filter((c) => {
      const deps = c.depends_on ?? [];
      return deps.every((d) => !phaseIds.has(d) || completed.has(d));
    });

    if (ready.length === 0) {
      // Defensive: should be unreachable because the graph is acyclic
      // and `buildPhases` only receives topo-sorted ids. Surface the
      // remaining ids so a regression is debuggable.
      groups.push(remaining.map((c) => c.id));
      break;
    }

    groups.push(ready.map((c) => c.id).sort());
    for (const c of ready) completed.add(c.id);
    remaining = remaining.filter((c) => !completed.has(c.id));
  }

  return groups;
}

/** Build a reverse-order rollback plan from an execution plan. */
export function buildRollbackPlan(plan: ExecutionPlan): {
  phases: Array<{ phase: number; components: ComponentStep[] }>;
  strategy: RollbackStrategy;
} {
  const rollbackPhases = [...plan.phases]
    .reverse()
    .map((phase) => ({
      phase: -phase.phase,
      components: [...phase.components].reverse(),
    }));
  return { phases: rollbackPhases, strategy: plan.rollback_strategy };
}

/**
 * Estimate total wall-clock duration for the plan using per-type heuristics
 * (matching the original Elixir constants) and a parallelism reduction.
 */
export function estimateDuration(plan: ExecutionPlan): {
  total_ms: number;
  adjusted_ms: number;
  parallel_factor: number;
  estimated_end_iso: string;
} {
  const totalMs = plan.phases
    .flatMap((p) => p.components)
    .map(estimateComponentDuration)
    .reduce((a, b) => a + b, 0);

  const parallelFactor = calculateParallelFactor(plan);
  const adjustedMs = Math.round(totalMs / parallelFactor);
  const end = new Date(Date.now() + adjustedMs).toISOString();

  return {
    total_ms: totalMs,
    adjusted_ms: adjustedMs,
    parallel_factor: parallelFactor,
    estimated_end_iso: end,
  };
}

const DURATION_HEURISTIC: Record<string, number> = {
  "cloud.provision": 180_000,
  "database.provision": 360_000,
  "container.build": 120_000,
  "kubernetes.deploy": 90_000,
  "observability.setup": 60_000,
  "secrets.create": 30_000,
  "git.create": 15_000,
};

function estimateComponentDuration(step: ComponentStep): number {
  return DURATION_HEURISTIC[step.type] ?? 60_000;
}

function calculateParallelFactor(plan: ExecutionPlan): number {
  const maxParallel = Math.max(
    1,
    ...plan.phases.flatMap((phase) =>
      phase.parallel.map((group) => group.length)
    ),
  );
  if (maxParallel <= 1) return 1;
  return Math.max(1.5, maxParallel / 2);
}

function getRollbackStrategy(stack: Stack): RollbackStrategy {
  const r = stack.rollback ?? {};
  return {
    enabled: r.enabled ?? false,
    strategy: r.strategy ?? "cascade",
    preserve_data: r.preserve_data ?? true,
    triggers: r.triggers ?? {},
  };
}

/**
 * Best-effort cycle reporter for {@link validateGraph}. Returns the id
 * sequence of one detected cycle, or an empty array if the graph is
 * acyclic. The detection algorithm is a depth-first colouring scheme.
 */
function findCycle(graph: DependencyGraph): string[] {
  const adjacency = new Map<string, string[]>();
  for (const id of graph.vertices.keys()) adjacency.set(id, []);
  for (const [from, to] of graph.edges) adjacency.get(from)!.push(to);

  const WHITE = 0, GREY = 1, BLACK = 2;
  const colour = new Map<string, number>();
  for (const id of graph.vertices.keys()) colour.set(id, WHITE);

  const stack: string[] = [];

  function dfs(u: string): string[] | null {
    colour.set(u, GREY);
    stack.push(u);
    for (const v of adjacency.get(u) ?? []) {
      if (colour.get(v) === GREY) {
        const idx = stack.indexOf(v);
        return stack.slice(idx).concat(v);
      }
      if (colour.get(v) === WHITE) {
        const found = dfs(v);
        if (found) return found;
      }
    }
    colour.set(u, BLACK);
    stack.pop();
    return null;
  }

  for (const id of graph.vertices.keys()) {
    if (colour.get(id) === WHITE) {
      const c = dfs(id);
      if (c) return c;
    }
  }
  return [];
}
