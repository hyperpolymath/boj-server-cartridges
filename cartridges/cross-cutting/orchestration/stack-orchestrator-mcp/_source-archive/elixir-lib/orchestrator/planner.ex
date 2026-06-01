# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyOrchestrator.Orchestrator.Planner do
  @moduledoc """
  Builds execution plans from parsed stacks.

  Responsibilities:
  - Topological sort of dependency graph
  - Parallel execution grouping
  - LSP server routing
  - Rollback planning
  - Security policy propagation
  """

  alias PolyOrchestrator.Orchestrator.StackParser

  @doc """
  Build an execution plan from a parsed stack.

  Returns:
  - `{:ok, plan}` - Executable plan with phases and steps
  - `{:error, reason}` - Planning error (cycles, missing deps, etc.)
  """
  def build_plan(stack) do
    with {:ok, graph} <- StackParser.extract_dependency_graph(stack),
         :ok <- validate_graph(graph),
         {:ok, sorted} <- topological_sort(graph),
         {:ok, phases} <- build_phases(sorted, stack) do
      plan = %{
        stack_id: stack["metadata"]["name"],
        phases: phases,
        security_policies: StackParser.extract_security_policies(stack),
        rollback_strategy: get_rollback_strategy(stack),
        verification: stack["verification"] || []
      }

      {:ok, plan}
    end
  end

  @doc """
  Validate the dependency graph for cycles and orphans.
  """
  def validate_graph(graph) do
    cond do
      Graph.is_cyclic?(graph) ->
        cycles = find_cycles(graph)
        {:error, "Cyclic dependencies detected: #{inspect(cycles)}"}

      true ->
        :ok
    end
  end

  @doc """
  Topological sort - order components by dependencies.
  """
  def topological_sort(graph) do
    case Graph.topsort(graph) do
      false -> {:error, "Cannot sort graph (cyclic dependencies)"}
      sorted -> {:ok, sorted}
    end
  end

  @doc """
  Build execution phases with parallel execution opportunities.

  Groups components that can run in parallel (no dependencies between them).
  """
  def build_phases(sorted_ids, stack) do
    components = stack["components"] || []
    component_map = Map.new(components, fn c -> {c["id"], c} end)

    phases =
      sorted_ids
      |> Enum.map(fn id -> Map.get(component_map, id) end)
      |> Enum.filter(&(&1 != nil))
      |> group_by_phase_number()
      |> Enum.map(fn {phase_num, comps} ->
        %{
          phase: phase_num,
          parallel: identify_parallel_components(comps),
          components: Enum.map(comps, &build_component_step/1)
        }
      end)

    {:ok, phases}
  end

  @doc """
  Build a component execution step.
  """
  def build_component_step(component) do
    %{
      id: component["id"],
      type: component["type"],
      lsp_server: component["lsp_server"],
      config: component["config"] || %{},
      depends_on: component["depends_on"] || [],
      outputs: %{},  # Populated during execution
      status: :pending
    }
  end

  @doc """
  Identify components that can run in parallel within a phase.

  Components can run in parallel if:
  1. They're in the same phase
  2. They don't depend on each other
  3. They use different LSP servers (optional optimization)
  """
  def identify_parallel_components(components) do
    component_ids = MapSet.new(components, & &1["id"])

    components
    |> Enum.chunk_by(fn c ->
      depends_on = MapSet.new(c["depends_on"] || [])
      # Can run in parallel if no dependencies within this phase
      MapSet.disjoint?(depends_on, component_ids)
    end)
    |> Enum.map(fn group ->
      Enum.map(group, & &1["id"])
    end)
  end

  @doc """
  Build rollback plan - reverse order with dependency awareness.
  """
  def build_rollback_plan(execution_plan) do
    phases = execution_plan.phases

    rollback_phases =
      phases
      |> Enum.reverse()
      |> Enum.map(fn phase ->
        %{
          phase: -phase.phase,  # Negative to indicate rollback
          components: Enum.reverse(phase.components)
        }
      end)

    %{
      phases: rollback_phases,
      strategy: execution_plan.rollback_strategy
    }
  end

  @doc """
  Estimate execution time based on component types.

  Uses heuristics:
  - cloud.provision: 2-5 minutes
  - database.provision: 3-10 minutes
  - container.build: 1-5 minutes
  - kubernetes.deploy: 1-3 minutes
  - observability.setup: 1-2 minutes
  """
  def estimate_duration(plan) do
    total_ms =
      plan.phases
      |> Enum.flat_map(& &1.components)
      |> Enum.map(&estimate_component_duration/1)
      |> Enum.sum()

    # Adjust for parallelism (rough estimate)
    parallel_factor = calculate_parallel_factor(plan)
    adjusted_ms = round(total_ms / parallel_factor)

    %{
      total_ms: total_ms,
      adjusted_ms: adjusted_ms,
      parallel_factor: parallel_factor,
      estimated_end: DateTime.add(DateTime.utc_now(), adjusted_ms, :millisecond)
    }
  end

  # Private functions

  defp find_cycles(graph) do
    # Simplified cycle detection - just return that cycles exist
    # A full implementation would identify the actual cycles
    Graph.vertices(graph)
  end

  defp group_by_phase_number(components) do
    components
    |> Enum.group_by(fn c -> c["phase"] || 1 end)
    |> Enum.sort_by(fn {phase, _} -> phase end)
  end

  defp get_rollback_strategy(stack) do
    rollback = stack["rollback"] || %{}

    %{
      enabled: rollback["enabled"] || false,
      strategy: rollback["strategy"] || "cascade",
      preserve_data: rollback["preserve_data"] || true,
      triggers: rollback["triggers"] || %{}
    }
  end

  defp estimate_component_duration(%{type: "cloud.provision"}), do: 180_000  # 3 min
  defp estimate_component_duration(%{type: "database.provision"}), do: 360_000  # 6 min
  defp estimate_component_duration(%{type: "container.build"}), do: 120_000  # 2 min
  defp estimate_component_duration(%{type: "kubernetes.deploy"}), do: 90_000  # 1.5 min
  defp estimate_component_duration(%{type: "observability.setup"}), do: 60_000  # 1 min
  defp estimate_component_duration(%{type: "secrets.create"}), do: 30_000  # 30 sec
  defp estimate_component_duration(%{type: "git.create"}), do: 15_000  # 15 sec
  defp estimate_component_duration(_), do: 60_000  # Default 1 min

  defp calculate_parallel_factor(plan) do
    # Count max parallel components across all phases
    max_parallel =
      plan.phases
      |> Enum.flat_map(fn phase -> phase.parallel || [] end)
      |> Enum.map(&length/1)
      |> Enum.max(fn -> 1 end)

    # If we have N components in parallel, we get roughly N/2 speedup (conservative)
    # But minimum speedup factor is 1.5 for any parallelism
    if max_parallel > 1, do: max(1.5, max_parallel / 2), else: 1
  end
end
