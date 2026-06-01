# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyObservability.Adapters.Jaeger do
  @moduledoc """
  Adapter for Jaeger - Distributed tracing platform.

  ## Configuration

  Jaeger uses environment variables or `jaeger-config.yml` for configuration.

  ## Commands

  - `jaeger-query` - Query traces
  - `jaeger-collector` - Receive traces
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
    config_files = ["jaeger-config.yml", "jaeger-config.yaml"]

    exists =
      Enum.any?(config_files, fn file ->
        File.exists?(Path.join(project_path, file))
      end)

    # Also check for docker-compose with Jaeger services
    docker_compose = Path.join(project_path, "docker-compose.yml")

    docker_has_jaeger =
      if File.exists?(docker_compose) do
        case File.read(docker_compose) do
          {:ok, content} ->
            String.contains?(content, "jaegertracing") || String.contains?(content, "jaeger")

          {:error, _} ->
            false
        end
      else
        false
      end

    {:ok, exists || docker_has_jaeger}
  end

  @impl PolyObservability.Adapters.Behaviour
  def query_metrics(_project_path, _query, _opts) do
    {:error, "Jaeger is for distributed tracing. Use Prometheus for metrics."}
  end

  @impl PolyObservability.Adapters.Behaviour
  def query_logs(_project_path, _query, _opts) do
    {:error, "Jaeger does not support log queries. Use Loki instead."}
  end

  @impl PolyObservability.Adapters.Behaviour
  def query_traces(project_path, query, opts) do
    GenServer.call(__MODULE__, {:query_traces, project_path, query, opts})
  end

  @impl PolyObservability.Adapters.Behaviour
  def list_dashboards(_project_path) do
    {:error, "Jaeger UI provides trace visualization. Use Grafana for custom dashboards."}
  end

  @impl PolyObservability.Adapters.Behaviour
  def alert_status(_project_path) do
    {:error, "Jaeger does not have built-in alerting. Use Grafana or Prometheus for alerts."}
  end

  @impl PolyObservability.Adapters.Behaviour
  def version do
    # Jaeger doesn't have a single CLI tool with --version
    # Check if jaeger-query is available
    case System.cmd("which", ["jaeger-query"], stderr_to_stdout: true) do
      {path, 0} when path != "" ->
        {:ok, "detected at #{String.trim(path)}"}

      _ ->
        {:error, "Jaeger binaries not found in PATH"}
    end
  end

  @impl PolyObservability.Adapters.Behaviour
  def metadata do
    %{
      name: "Jaeger",
      description: "Open-source distributed tracing platform for monitoring and troubleshooting microservices",
      config_files: ["jaeger-config.yml", "jaeger-config.yaml", "docker-compose.yml"],
      query_language: nil
    }
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %{traces: %{}}}
  end

  @impl true
  def handle_call({:query_traces, _project_path, query, opts}, _from, state) do
    Logger.info("Querying Jaeger traces: #{query}")

    # Jaeger CLI doesn't exist, so we use the HTTP API directly
    jaeger_url = opts[:jaeger_url] || "http://localhost:16686"

    params = %{
      service: opts[:service],
      operation: opts[:operation],
      start: opts[:start_time],
      end: opts[:end_time],
      limit: opts[:limit] || 20,
      lookback: opts[:lookback] || "1h"
    }

    # Build query URL
    query_params =
      params
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.map(fn {k, v} -> "#{k}=#{URI.encode_www_form(to_string(v))}" end)
      |> Enum.join("&")

    url = "#{jaeger_url}/api/traces?#{query_params}"

    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        result = %{
          success: true,
          traces: parse_jaeger_response(body),
          query: query
        }

        {:reply, {:ok, result}, state}

      {:ok, %{status: status, body: body}} ->
        {:reply, {:error, "Query failed (HTTP #{status}): #{inspect(body)}"}, state}

      {:error, error} ->
        {:reply, {:error, "Request failed: #{inspect(error)}"}, state}
    end
  end

  # Private helpers

  defp parse_jaeger_response(body) when is_map(body) do
    # Extract traces from Jaeger API response
    traces = body["data"] || []

    Enum.map(traces, fn trace ->
      %{
        trace_id: trace["traceID"],
        spans: length(trace["spans"] || []),
        duration: calculate_duration(trace["spans"]),
        services: extract_services(trace["spans"])
      }
    end)
  end

  defp parse_jaeger_response(_body), do: []

  defp calculate_duration(nil), do: 0

  defp calculate_duration(spans) when is_list(spans) do
    Enum.reduce(spans, 0, fn span, acc ->
      acc + (span["duration"] || 0)
    end)
  end

  defp extract_services(nil), do: []

  defp extract_services(spans) when is_list(spans) do
    spans
    |> Enum.map(fn span -> get_in(span, ["process", "serviceName"]) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end
end
