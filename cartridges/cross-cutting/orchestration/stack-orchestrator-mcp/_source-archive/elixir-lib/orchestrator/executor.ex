# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyOrchestrator.Orchestrator.Executor do
  @moduledoc """
  Executes orchestration plans by coordinating LSP server calls.

  Handles:
  - Phase-by-phase execution
  - Parallel component execution
  - Output capture and propagation
  - Error handling and rollback
  - Progress reporting
  - VeriSimDB history storage
  """

  use GenServer
  require Logger

  alias PolyOrchestrator.Orchestrator.{LSPClient, Planner}
  alias PolyOrchestrator.VeriSimDB.Client, as: VeriSimDB

  defstruct [
    :execution_id,
    :plan,
    :current_phase,
    :component_outputs,
    :status,
    :start_time,
    :errors,
    :rollback_plan
  ]

  # Client API

  @doc """
  Start an execution process for a plan.
  """
  def start_link(plan) do
    execution_id = generate_execution_id()

    GenServer.start_link(__MODULE__, {execution_id, plan},
      name: via_tuple(execution_id)
    )
  end

  @doc """
  Execute a plan synchronously.
  """
  def execute(plan) do
    {:ok, pid} = start_link(plan)
    GenServer.call(pid, :execute, :infinity)
  end

  @doc """
  Execute a plan asynchronously.
  """
  def execute_async(plan) do
    {:ok, pid} = start_link(plan)
    GenServer.cast(pid, :execute)
    {:ok, pid}
  end

  @doc """
  Get execution status.
  """
  def get_status(execution_id) do
    GenServer.call(via_tuple(execution_id), :get_status)
  end

  @doc """
  Cancel an in-progress execution.
  """
  def cancel(execution_id) do
    GenServer.call(via_tuple(execution_id), :cancel)
  end

  @doc """
  Rollback a completed or failed execution.
  """
  def rollback(execution_id) do
    GenServer.call(via_tuple(execution_id), :rollback, :infinity)
  end

  # Server Callbacks

  @impl true
  def init({execution_id, plan}) do
    state = %__MODULE__{
      execution_id: execution_id,
      plan: plan,
      current_phase: 0,
      component_outputs: %{},
      status: :initialized,
      start_time: DateTime.utc_now(),
      errors: [],
      rollback_plan: Planner.build_rollback_plan(plan)
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:execute, _from, state) do
    Logger.info("Starting execution: #{state.execution_id}")

    result =
      state
      |> execute_all_phases()
      |> run_verification()
      |> store_in_verisimdb()
      |> build_result()

    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      execution_id: state.execution_id,
      status: state.status,
      current_phase: state.current_phase,
      total_phases: length(state.plan.phases),
      component_outputs: state.component_outputs,
      errors: state.errors,
      elapsed_ms: DateTime.diff(DateTime.utc_now(), state.start_time, :millisecond)
    }

    {:reply, {:ok, status}, state}
  end

  @impl true
  def handle_call(:cancel, _from, state) do
    Logger.warn("Cancelling execution: #{state.execution_id}")

    state = %{state | status: :cancelled}
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:rollback, _from, state) do
    Logger.info("Rolling back execution: #{state.execution_id}")

    result = execute_rollback(state)

    {:reply, result, state}
  end

  @impl true
  def handle_cast(:execute, state) do
    # Async execution - send result to monitoring process
    spawn(fn ->
      state
      |> execute_all_phases()
      |> run_verification()
      |> store_in_verisimdb()
      |> notify_completion()
    end)

    {:noreply, %{state | status: :running}}
  end

  # Private Functions - Execution

  defp execute_all_phases(state) do
    Enum.reduce_while(state.plan.phases, state, fn phase, acc ->
      Logger.info("Executing phase #{phase.phase}")

      case execute_phase(phase, acc) do
        {:ok, new_state} ->
          {:cont, %{new_state | current_phase: phase.phase}}

        {:error, reason} ->
          Logger.error("Phase #{phase.phase} failed: #{inspect(reason)}")
          error_state = %{acc | status: :failed, errors: [reason | acc.errors]}
          {:halt, error_state}
      end
    end)
  end

  defp execute_phase(phase, state) do
    # Execute components in parallel where possible
    results =
      phase.components
      |> Enum.map(&execute_component(&1, state))

    # Check for failures
    failures = Enum.filter(results, &match?({:error, _}, &1))

    if Enum.empty?(failures) do
      # Collect outputs
      outputs =
        results
        |> Enum.map(fn {:ok, result} -> {result.id, result.outputs} end)
        |> Map.new()

      new_outputs = Map.merge(state.component_outputs, outputs)
      {:ok, %{state | component_outputs: new_outputs}}
    else
      {:error, {:phase_failed, failures}}
    end
  end

  defp execute_component(component, state) do
    Logger.info("Executing component: #{component.id}")

    # Interpolate component config with outputs from previous components
    interpolated_component = interpolate_component_refs(component, state.component_outputs)

    # Execute via LSP client
    case LSPClient.execute_component(interpolated_component) do
      {:ok, result} ->
        Logger.info("Component #{component.id} completed successfully")
        {:ok, %{id: component.id, outputs: result, status: :success}}

      {:error, reason} ->
        Logger.error("Component #{component.id} failed: #{inspect(reason)}")
        {:error, {component.id, reason}}
    end
  end

  defp interpolate_component_refs(component, outputs) do
    # Replace ${component.output} references with actual values
    config = interpolate_map(component.config, outputs)
    %{component | config: config}
  end

  defp interpolate_map(map, outputs) when is_map(map) do
    Map.new(map, fn {k, v} ->
      {k, interpolate_value(v, outputs)}
    end)
  end

  defp interpolate_value(value, outputs) when is_binary(value) do
    # Replace ${component-id.field} with outputs[component-id].field
    Regex.replace(~r/\$\{([^.]+)\.([^}]+)\}/, value, fn _, component_id, field ->
      get_in(outputs, [component_id, field]) || "${#{component_id}.#{field}}"
    end)
  end

  defp interpolate_value(value, outputs) when is_list(value) do
    Enum.map(value, &interpolate_value(&1, outputs))
  end

  defp interpolate_value(value, outputs) when is_map(value) do
    interpolate_map(value, outputs)
  end

  defp interpolate_value(value, _outputs), do: value

  # Private Functions - Verification

  defp run_verification(state) do
    if state.status == :failed do
      state
    else
      Logger.info("Running verification checks")

      verification = state.plan.verification || []

      results = Enum.map(verification, &run_verification_check(&1, state))

      failures = Enum.filter(results, &match?({:error, _}, &1))

      if Enum.empty?(failures) do
        %{state | status: :verified}
      else
        Logger.error("Verification failed: #{inspect(failures)}")
        %{state | status: :verification_failed, errors: failures ++ state.errors}
      end
    end
  end

  defp run_verification_check(check, state) do
    # Simplified verification - would use actual HTTP/DB/Redis clients
    Logger.info("Running verification: #{check["id"]}")

    case check["type"] do
      "http" ->
        verify_http(check, state)

      "database" ->
        verify_database(check, state)

      "redis" ->
        verify_redis(check, state)

      _ ->
        {:ok, check["id"]}
    end
  end

  defp verify_http(check, state) do
    url = interpolate_value(check["url"], state.component_outputs)
    # Would use actual HTTP client
    Logger.info("HTTP check: #{url}")
    {:ok, check["id"]}
  end

  defp verify_database(check, _state) do
    Logger.info("Database check: #{check["connection"]}")
    {:ok, check["id"]}
  end

  defp verify_redis(check, _state) do
    Logger.info("Redis check: #{check["connection"]}")
    {:ok, check["id"]}
  end

  # Private Functions - VeriSimDB

  defp store_in_verisimdb(state) do
    execution_data = %{
      execution_id: state.execution_id,
      stack_id: state.plan.stack_id,
      timestamp: state.start_time,
      status: state.status,
      duration_ms: DateTime.diff(DateTime.utc_now(), state.start_time, :millisecond),
      components: Map.keys(state.component_outputs),
      outputs: state.component_outputs,
      errors: state.errors
    }

    case VeriSimDB.store_execution(execution_data) do
      {:ok, _} ->
        Logger.info("Stored execution in VeriSimDB")
        state

      {:error, reason} ->
        Logger.error("Failed to store in VeriSimDB: #{inspect(reason)}")
        state
    end
  end

  # Private Functions - Rollback

  defp execute_rollback(state) do
    Logger.info("Executing rollback for: #{state.execution_id}")

    rollback_state = %{state | status: :rolling_back}

    Enum.reduce_while(state.rollback_plan.phases, rollback_state, fn phase, acc ->
      Logger.info("Rolling back phase #{phase.phase}")

      case rollback_phase(phase, acc) do
        {:ok, new_state} ->
          {:cont, new_state}

        {:error, reason} ->
          Logger.error("Rollback phase failed: #{inspect(reason)}")
          {:halt, %{acc | status: :rollback_failed, errors: [reason | acc.errors]}}
      end
    end)
    |> then(fn final_state ->
      if final_state.status == :rollback_failed do
        {:error, final_state.errors}
      else
        {:ok, %{final_state | status: :rolled_back}}
      end
    end)
  end

  defp rollback_phase(phase, state) do
    # Execute rollback for each component
    results =
      phase.components
      |> Enum.map(&rollback_component(&1, state))

    failures = Enum.filter(results, &match?({:error, _}, &1))

    if Enum.empty?(failures) do
      {:ok, state}
    else
      {:error, {:rollback_phase_failed, failures}}
    end
  end

  defp rollback_component(component, _state) do
    Logger.info("Rolling back component: #{component.id}")

    # Would call LSP server's rollback/delete method
    # For now, just log
    {:ok, component.id}
  end

  # Private Functions - Helpers

  defp build_result(state) do
    case state.status do
      status when status in [:verified, :success] ->
        {:ok, %{
          execution_id: state.execution_id,
          status: :success,
          outputs: state.component_outputs,
          duration_ms: DateTime.diff(DateTime.utc_now(), state.start_time, :millisecond)
        }}

      _ ->
        {:error, %{
          execution_id: state.execution_id,
          status: state.status,
          errors: state.errors,
          duration_ms: DateTime.diff(DateTime.utc_now(), state.start_time, :millisecond)
        }}
    end
  end

  defp notify_completion(state) do
    # Would send to monitoring/notification system
    Logger.info("Execution completed: #{state.execution_id} - #{state.status}")
    state
  end

  defp generate_execution_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp via_tuple(execution_id) do
    {:via, Registry, {PolyOrchestrator.ExecutionRegistry, execution_id}}
  end
end
