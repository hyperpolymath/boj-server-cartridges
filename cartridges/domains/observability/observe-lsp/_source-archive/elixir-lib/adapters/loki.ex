# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyObservability.Adapters.Loki do
  @moduledoc """
  Adapter for Loki - Log aggregation system inspired by Prometheus.

  ## Configuration

  Loki uses `loki.yaml` or `loki-config.yaml` for configuration.

  ## Commands

  - `logcli query` - Query logs using LogQL
  - `logcli labels` - List available labels
  - `logcli series` - Query series
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
    config_files = ["loki.yaml", "loki-config.yaml", "loki-local-config.yaml"]

    exists =
      Enum.any?(config_files, fn file ->
        File.exists?(Path.join(project_path, file))
      end)

    {:ok, exists}
  end

  @impl PolyObservability.Adapters.Behaviour
  def query_metrics(_project_path, _query, _opts) do
    {:error, "Loki is for log aggregation. Use Prometheus for metrics."}
  end

  @impl PolyObservability.Adapters.Behaviour
  def query_logs(project_path, query, opts) do
    GenServer.call(__MODULE__, {:query_logs, project_path, query, opts})
  end

  @impl PolyObservability.Adapters.Behaviour
  def query_traces(_project_path, _query, _opts) do
    {:error, "Loki does not support trace queries. Use Jaeger or Tempo instead."}
  end

  @impl PolyObservability.Adapters.Behaviour
  def list_dashboards(_project_path) do
    {:error, "Loki does not have built-in dashboards. Use Grafana for visualization."}
  end

  @impl PolyObservability.Adapters.Behaviour
  def alert_status(_project_path) do
    {:error, "Loki alerting is configured through Grafana or Prometheus Alertmanager."}
  end

  @impl PolyObservability.Adapters.Behaviour
  def version do
    case System.cmd("logcli", ["--version"], stderr_to_stdout: true) do
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
      name: "Loki",
      description: "Horizontally-scalable, highly-available log aggregation system inspired by Prometheus",
      config_files: ["loki.yaml", "loki-config.yaml", "loki-local-config.yaml"],
      query_language: "LogQL"
    }
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %{queries: %{}}}
  end

  @impl true
  def handle_call({:query_logs, project_path, query, opts}, _from, state) do
    Logger.info("Executing Loki query: #{query}")

    args = ["query", query]

    args = if opts[:limit], do: args ++ ["--limit", to_string(opts[:limit])], else: args

    args =
      if opts[:start_time], do: args ++ ["--since", format_time(opts[:start_time])], else: args

    args = if opts[:end_time], do: args ++ ["--to", format_time(opts[:end_time])], else: args

    args =
      if opts[:direction],
        do: args ++ ["--forward", to_string(opts[:direction] == "forward")],
        else: args

    # Set Loki URL from environment or default
    env = [{"LOKI_ADDR", opts[:loki_addr] || "http://localhost:3100"}]

    case System.cmd("logcli", args, cd: project_path, stderr_to_stdout: true, env: env) do
      {output, 0} ->
        result = %{
          success: true,
          logs: parse_logcli_output(output),
          query: query
        }

        {:reply, {:ok, result}, state}

      {error, exit_code} ->
        {:reply, {:error, "Query failed (exit #{exit_code}): #{error}"}, state}
    end
  end

  # Private helpers

  defp format_time(time) when is_binary(time), do: time
  defp format_time(time) when is_integer(time), do: to_string(time) <> "s"

  defp parse_logcli_output(output) do
    # Basic parsing - split by newlines
    # In production, parse timestamp and log line properly
    output
    |> String.split("\n")
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&%{line: &1})
  end
end
