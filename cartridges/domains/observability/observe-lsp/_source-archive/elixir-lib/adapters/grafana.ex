# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyObservability.Adapters.Grafana do
  @moduledoc """
  Adapter for Grafana - Observability and data visualization platform.

  ## Configuration

  Grafana uses `grafana.ini` or environment variables for configuration.

  ## Commands

  - `grafana-cli plugins list` - List installed plugins
  - `grafana-cli admin reset-admin-password` - Reset admin password
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
    config_path = Path.join(project_path, "grafana.ini")
    config_dir = Path.join(project_path, "grafana")
    {:ok, File.exists?(config_path) || File.dir?(config_dir)}
  end

  @impl PolyObservability.Adapters.Behaviour
  def query_metrics(_project_path, _query, _opts) do
    {:error, "Grafana delegates metric queries to datasources (Prometheus, InfluxDB, etc.)"}
  end

  @impl PolyObservability.Adapters.Behaviour
  def query_logs(_project_path, _query, _opts) do
    {:error, "Grafana delegates log queries to datasources (Loki, Elasticsearch, etc.)"}
  end

  @impl PolyObservability.Adapters.Behaviour
  def query_traces(_project_path, _query, _opts) do
    {:error, "Grafana delegates trace queries to datasources (Jaeger, Tempo, etc.)"}
  end

  @impl PolyObservability.Adapters.Behaviour
  def list_dashboards(project_path) do
    GenServer.call(__MODULE__, {:list_dashboards, project_path})
  end

  @impl PolyObservability.Adapters.Behaviour
  def alert_status(project_path) do
    GenServer.call(__MODULE__, {:alert_status, project_path})
  end

  @impl PolyObservability.Adapters.Behaviour
  def version do
    case System.cmd("grafana-cli", ["--version"], stderr_to_stdout: true) do
      {output, 0} ->
        version =
          output
          |> String.trim()
          |> String.split()
          |> List.last()

        {:ok, version || "unknown"}

      {error, _} ->
        {:error, error}
    end
  end

  @impl PolyObservability.Adapters.Behaviour
  def metadata do
    %{
      name: "Grafana",
      description: "Open-source platform for monitoring and observability with dashboards and alerting",
      config_files: ["grafana.ini", "grafana/"],
      query_language: nil
    }
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %{dashboards: %{}, alerts: %{}}}
  end

  @impl true
  def handle_call({:list_dashboards, project_path}, _from, state) do
    Logger.info("Listing Grafana dashboards at #{project_path}")

    dashboard_dir = Path.join(project_path, "grafana/dashboards")

    if File.dir?(dashboard_dir) do
      dashboards =
        File.ls!(dashboard_dir)
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.map(fn filename ->
          path = Path.join(dashboard_dir, filename)

          case File.read(path) do
            {:ok, content} ->
              case Jason.decode(content) do
                {:ok, dashboard} ->
                  %{
                    filename: filename,
                    title: get_in(dashboard, ["dashboard", "title"]) || filename,
                    uid: get_in(dashboard, ["dashboard", "uid"]),
                    path: path
                  }

                {:error, _} ->
                  %{filename: filename, title: filename, error: "Invalid JSON", path: path}
              end

            {:error, _} ->
              %{filename: filename, error: "Cannot read file", path: path}
          end
        end)

      {:reply, {:ok, dashboards}, state}
    else
      {:reply, {:ok, []}, state}
    end
  end

  @impl true
  def handle_call({:alert_status, project_path}, _from, state) do
    Logger.info("Checking Grafana alert status at #{project_path}")

    alert_dir = Path.join(project_path, "grafana/alerts")

    if File.dir?(alert_dir) do
      alerts =
        File.ls!(alert_dir)
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.map(fn filename ->
          path = Path.join(alert_dir, filename)

          case File.read(path) do
            {:ok, content} ->
              case Jason.decode(content) do
                {:ok, alert} ->
                  %{
                    filename: filename,
                    title: alert["title"] || filename,
                    condition: alert["condition"],
                    path: path
                  }

                {:error, _} ->
                  %{filename: filename, error: "Invalid JSON", path: path}
              end

            {:error, _} ->
              %{filename: filename, error: "Cannot read file", path: path}
          end
        end)

      result = %{
        alert_count: length(alerts),
        alerts: alerts
      }

      {:reply, {:ok, result}, state}
    else
      {:reply, {:ok, %{alert_count: 0, alerts: []}}, state}
    end
  end
end
