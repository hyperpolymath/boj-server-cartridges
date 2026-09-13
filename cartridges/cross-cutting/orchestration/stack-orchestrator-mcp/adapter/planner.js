// SPDX-License-Identifier: MPL-2.0
import {
  extractDependencyGraph,
  extractSecurityPolicies
} from "./parser.js";
import { err, ok } from "./types.js";
export function buildPlan(stack) {
  const graph = extractDependencyGraph(stack), graphResult = validateGraph(graph);
  if (!graphResult.ok)
    return graphResult;
  const sortedResult = topologicalSort(graph);
  if (!sortedResult.ok)
    return sortedResult;
  const phasesResult = buildPhases(sortedResult.value, stack);
  if (!phasesResult.ok)
    return phasesResult;
  return ok({
    stack_id: stack.metadata.name,
    phases: phasesResult.value,
    security_policies: extractSecurityPolicies(stack),
    rollback_strategy: getRollbackStrategy(stack),
    verification: stack.verification ?? []
  });
}
export function validateGraph(graph) {
  for (const [from, to] of graph.edges) {
    if (!graph.vertices.has(from))
      return err(`Dependency edge references unknown component: ${from}`);
    if (!graph.vertices.has(to))
      return err(`Dependency edge references unknown component: ${to}`);
  }
  const cycle = findCycle(graph);
  if (cycle.length > 0)
    return err(`Cyclic dependencies detected: ${cycle.join(" \u2192 ")}`);
  return ok(!0);
}
export function topologicalSort(graph) {
  const inDegree = new Map, adjacency = new Map;
  for (const id of graph.vertices.keys()) {
    inDegree.set(id, 0);
    adjacency.set(id, []);
  }
  for (const [from, to] of graph.edges) {
    inDegree.set(to, (inDegree.get(to) ?? 0) + 1);
    adjacency.get(from).push(to);
  }
  const ready = [];
  for (const [id, deg] of inDegree)
    if (deg === 0)
      ready.push(id);
  ready.sort();
  const sorted = [];
  while (ready.length > 0) {
    const id = ready.shift();
    sorted.push(id);
    for (const next of adjacency.get(id) ?? []) {
      const d = (inDegree.get(next) ?? 0) - 1;
      inDegree.set(next, d);
      if (d === 0) {
        const insertAt = ready.findIndex((r) => r > next);
        if (insertAt === -1)
          ready.push(next);
        else
          ready.splice(insertAt, 0, next);
      }
    }
  }
  if (sorted.length !== graph.vertices.size)
    return err("Cannot sort graph (cyclic dependencies)");
  return ok(sorted);
}
export function buildPhases(sortedIds, stack) {
  const components = stack.components ?? [], componentMap = new Map(components.map((c) => [c.id, c])), sortedComponents = [];
  for (const id of sortedIds) {
    const c = componentMap.get(id);
    if (c)
      sortedComponents.push(c);
  }
  const phaseGroups = new Map;
  for (const c of sortedComponents) {
    const p = c.phase ?? 1;
    if (!phaseGroups.has(p))
      phaseGroups.set(p, []);
    phaseGroups.get(p).push(c);
  }
  const phases = [], phaseNumbers = [...phaseGroups.keys()].sort((a, b) => a - b);
  for (const phaseNum of phaseNumbers) {
    const comps = phaseGroups.get(phaseNum);
    phases.push({
      phase: phaseNum,
      parallel: identifyParallelComponents(comps),
      components: comps.map(buildComponentStep)
    });
  }
  return ok(phases);
}
export function buildComponentStep(component) {
  return {
    id: component.id,
    type: component.type,
    lsp_server: component.lsp_server,
    config: component.config ?? {},
    depends_on: component.depends_on ?? [],
    outputs: {},
    status: "pending"
  };
}
export function identifyParallelComponents(components) {
  const phaseIds = new Set(components.map((c) => c.id)), completed = new Set, groups = [];
  let remaining = [...components];
  while (remaining.length > 0) {
    const ready = remaining.filter((c) => {
      return (c.depends_on ?? []).every((d) => !phaseIds.has(d) || completed.has(d));
    });
    if (ready.length === 0) {
      groups.push(remaining.map((c) => c.id));
      break;
    }
    groups.push(ready.map((c) => c.id).sort());
    for (const c of ready)
      completed.add(c.id);
    remaining = remaining.filter((c) => !completed.has(c.id));
  }
  return groups;
}
export function buildRollbackPlan(plan) {
  return { phases: [...plan.phases].reverse().map((phase) => ({
    phase: -phase.phase,
    components: [...phase.components].reverse()
  })), strategy: plan.rollback_strategy };
}
export function estimateDuration(plan) {
  const totalMs = plan.phases.flatMap((p) => p.components).map(estimateComponentDuration).reduce((a, b) => a + b, 0), parallelFactor = calculateParallelFactor(plan), adjustedMs = Math.round(totalMs / parallelFactor), end = new Date(Date.now() + adjustedMs).toISOString();
  return {
    total_ms: totalMs,
    adjusted_ms: adjustedMs,
    parallel_factor: parallelFactor,
    estimated_end_iso: end
  };
}
const DURATION_HEURISTIC = {
  "cloud.provision": 180000,
  "database.provision": 360000,
  "container.build": 120000,
  "kubernetes.deploy": 90000,
  "observability.setup": 60000,
  "secrets.create": 30000,
  "git.create": 15000
};
function estimateComponentDuration(step) {
  return DURATION_HEURISTIC[step.type] ?? 60000;
}
function calculateParallelFactor(plan) {
  const maxParallel = Math.max(1, ...plan.phases.flatMap((phase) => phase.parallel.map((group) => group.length)));
  if (maxParallel <= 1)
    return 1;
  return Math.max(1.5, maxParallel / 2);
}
function getRollbackStrategy(stack) {
  const r = stack.rollback ?? {};
  return {
    enabled: r.enabled ?? !1,
    strategy: r.strategy ?? "cascade",
    preserve_data: r.preserve_data ?? !0,
    triggers: r.triggers ?? {}
  };
}
function findCycle(graph) {
  const adjacency = new Map;
  for (const id of graph.vertices.keys())
    adjacency.set(id, []);
  for (const [from, to] of graph.edges)
    adjacency.get(from).push(to);
  const WHITE = 0, GREY = 1, BLACK = 2, colour = new Map;
  for (const id of graph.vertices.keys())
    colour.set(id, WHITE);
  const stack = [];
  function dfs(u) {
    colour.set(u, GREY);
    stack.push(u);
    for (const v of adjacency.get(u) ?? []) {
      if (colour.get(v) === GREY) {
        const idx = stack.indexOf(v);
        return stack.slice(idx).concat(v);
      }
      if (colour.get(v) === WHITE) {
        const found = dfs(v);
        if (found)
          return found;
      }
    }
    colour.set(u, BLACK);
    stack.pop();
    return null;
  }
  for (const id of graph.vertices.keys())
    if (colour.get(id) === WHITE) {
      const c = dfs(id);
      if (c)
        return c;
    }
  return [];
}
