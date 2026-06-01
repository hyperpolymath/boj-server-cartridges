# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyObservability.Adapters.Prometheus do
  @moduledoc """
  Adapter for Prometheus - Monitoring and alerting toolkit.

  ## Configuration

  Prometheus uses `prometheus.yml` at the project root.

  ## Commands

  - `promtool check config` - Validate configuration
  - `promtool query instant` - Execute instant query
  - `promtool query range` - Execute range query
  """
  use GenServer
  @behaviour PolyObservability.Adapters.Behaviour

  require Logger

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl PolyObservability.Adapters.Behaviour
  def detect(project_path) do
    config_path = Path.join(project_path, "prometheus.yml")
    {:ok, File.exists?(config_path)}
  end

  @impl PolyObservability.Adapters.Behaviour
  def query_metrics(project_path, query, opts) do
    GenServer.call(__MODULE__, {:query_metrics, project_path, query, opts})
  end

  @impl PolyObservability.Adapters.Behaviour
  def query_logs(_project_path, _query, _opts) do
    {:error, "Prometheus does not support log queries. Use Loki instead."}
  end

  @impl PolyObservability.Adapters.Behaviour
  def query_traces(_project_path, _query, _opts) do
    {:error, "Prometheus does not support trace queries. Use Jaeger instead."}
  end

  @impl PolyObservability.Adapters.Behaviour
  def list_dashboards(_project_path) do
    {:error, "Prometheus does not have built-in dashboards. Use Grafana for visualization."}
  end

  @impl PolyObservability.Adapters.Behaviour
  def alert_status(project_path) do
    GenServer.call(__MODULE__, {:alert_status, project_path})
  end

  @impl PolyObservability.Adapters.Behaviour
  def version do
    case System.cmd("promtool", ["--version"], stderr_to_stdout: true) do
      {output, 0} ->
        version =
          output
          |> String.split("\n")
          |> Enum.find(&String.contains?(&1, "version"))
          |> then(&(Regex.run(~r/version ([^\s]+)/, &1 || "") || []))
          |> List.last()

        {:ok, version || "unknown"}

      {error, _} ->
        {:error, error}
    end
  end

  @impl PolyObservability.Adapters.Behaviour
  def metadata do
    %{
      name: "Prometheus",
      description: "Monitoring system with time series database and PromQL query language",
      config_files: ["prometheus.yml"],
      query_language: "PromQL"
    }
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %{queries: %{}, alerts: %{}}}
  end

  @impl true
  def handle_call({:query_metrics, project_path, query, opts}, _from, state) do
    Logger.info("Executing Prometheus query: #{query}")

    query_type = if opts[:range], do: "range", else: "instant"
    args = ["query", query_type, query]

    args =
      if opts[:start_time], do: args ++ ["--start", format_time(opts[:start_time])], else: args

    args = if opts[:end_time], do: args ++ ["--end", format_time(opts[:end_time])], else: args
    args = if opts[:step], do: args ++ ["--step", opts[:step]], else: args

    case System.cmd("promtool", args, cd: project_path, stderr_to_stdout: true) do
      {output, 0} ->
        result = %{
          success: true,
          data: parse_promtool_output(output),
          query: query
        }

        {:reply, {:ok, result}, state}

      {error, exit_code} ->
        {:reply, {:error, "Query failed (exit #{exit_code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:alert_status, project_path}, _from, state) do
    Logger.info("Checking Prometheus alerts at #{project_path}")

    config_path = Path.join(project_path, "prometheus.yml")

    case System.cmd("promtool", ["check", "config", config_path], stderr_to_stdout: true) do
      {output, 0} ->
        result = %{
          config_valid: true,
          message: output
        }

        {:reply, {:ok, result}, state}

      {error, exit_code} ->
        {:reply, {:error, "Alert check failed (exit #{exit_code}): #{error}"}, state}
    end
  end

  # Private helpers

  defp format_time(time) when is_binary(time), do: time
  defp format_time(time) when is_integer(time), do: to_string(time)

  defp parse_promtool_output(output) do
    # Basic parsing - in production, this would parse the promtool output format
    %{raw: output}
  end
end
