// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

// Domain types for stack-orchestrator-mcp.
// Direct port of the implicit Elixir map shapes in
// polystack/poly-orchestrator-lsp/lib/orchestrator/{stack_parser,planner}.ex.

export interface StackMetadata {
  name: string;
  version: string;
  description?: string;
  author?: string;
}

export interface Component {
  id: string;
  type: string;
  lsp_server: string;
  depends_on?: string[];
  phase?: number;
  config?: Record<string, unknown>;
}

export interface SecuritySection {
  threat_model?: string;
  attack_surface_score?: number;
  validated?: boolean;
  policies?: string[];
  constraints?: string[];
}

export interface Orchestration {
  max_parallel?: number;
  timeout_ms?: number;
  retry_count?: number;
  variables?: Record<string, string>;
}

export interface Rollback {
  enabled?: boolean;
  strategy?: string;
  preserve_data?: boolean;
  triggers?: Record<string, unknown>;
}

export interface VerificationStep {
  name?: string;
  command?: string;
  [key: string]: unknown;
}

export interface Stack {
  metadata: StackMetadata;
  components: Component[];
  security?: SecuritySection;
  orchestration?: Orchestration;
  rollback?: Rollback;
  verification?: VerificationStep[];
}

export interface SecurityPolicies {
  threat_model: string | undefined;
  attack_surface_score: number | undefined;
  validated: boolean;
  policies: string[];
  constraints: string[];
}

export interface ComponentStep {
  id: string;
  type: string;
  lsp_server: string;
  config: Record<string, unknown>;
  depends_on: string[];
  outputs: Record<string, unknown>;
  status: "pending" | "running" | "succeeded" | "failed" | "rolled_back";
}

export interface Phase {
  phase: number;
  parallel: string[][];
  components: ComponentStep[];
}

export interface RollbackStrategy {
  enabled: boolean;
  strategy: string;
  preserve_data: boolean;
  triggers: Record<string, unknown>;
}

export interface ExecutionPlan {
  stack_id: string;
  phases: Phase[];
  security_policies: SecurityPolicies;
  rollback_strategy: RollbackStrategy;
  verification: VerificationStep[];
}

export type Result<T, E = string> = { ok: true; value: T } | { ok: false; error: E };

export function ok<T>(value: T): Result<T, never> {
  return { ok: true, value };
}

export function err<E>(error: E): Result<never, E> {
  return { ok: false, error };
}
