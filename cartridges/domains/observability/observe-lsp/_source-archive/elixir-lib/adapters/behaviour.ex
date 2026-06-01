# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyObservability.Adapters.Behaviour do
  @moduledoc """
  Behaviour defining the contract for observability tool adapters.

  Each adapter implements this behaviour to provide a consistent interface
  for detecting, querying, and managing observability tools like Prometheus,
  Grafana, Loki, and Jaeger.

  ## Example

      defmodule PolyObservability.Adapters.Prometheus do
        use GenServer
        @behaviour PolyObservability.Adapters.Behaviour

        @impl true
        def detect(project_path) do
          config_exists = File.exists?(Path.join(project_path, "prometheus.yml"))
          {:ok, config_exists}
        end

        @impl true
        def query_metrics(project_path, query, opts) do
          # Execute PromQL query
        end
      end
  """

  @type project_path :: String.t()
  @type query :: String.t()
  @type opts :: keyword()
  @type result :: {:ok, map()} | {:error, String.t()}
  @type detect_result :: {:ok, boolean()} | {:error, String.t()}

  @doc """
  Detect if this observability tool is present in the project directory.

  Returns `{:ok, true}` if the tool's config file exists, `{:ok, false}` otherwise.
  """
  @callback detect(project_path) :: detect_result

  @doc """
  Query metrics from the observability tool.

  ## Options

  - `:start_time` - Start time for the query (ISO 8601 or Unix timestamp)
  - `:end_time` - End time for the query (ISO 8601 or Unix timestamp)
  - `:step` - Query resolution step (e.g., "15s", "1m")
  - `:timeout` - Query timeout in milliseconds
  """
  @callback query_metrics(project_path, query, opts) :: result

  @doc """
  Query logs from the observability tool.

  ## Options

  - `:start_time` - Start time for the query
  - `:end_time` - End time for the query
  - `:limit` - Maximum number of log lines to return
  - `:direction` - "forward" or "backward"
  """
  @callback query_logs(project_path, query, opts) :: result

  @doc """
  Query traces from the observability tool.

  ## Options

  - `:service` - Service name to filter traces
  - `:operation` - Operation name to filter traces
  - `:start_time` - Start time for the query
  - `:end_time` - End time for the query
  - `:limit` - Maximum number of traces to return
  """
  @callback query_traces(project_path, query, opts) :: result

  @doc """
  List available dashboards.

  Returns a list of dashboard metadata.
  """
  @callback list_dashboards(project_path) :: {:ok, [map()]} | {:error, String.t()}

  @doc """
  Get alert status.

  Returns current alert status and active alerts.
  """
  @callback alert_status(project_path) :: {:ok, map()} | {:error, String.t()}

  @doc """
  Get tool version.
  """
  @callback version() :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Get tool metadata (name, description, config files).
  """
  @callback metadata() :: %{
              name: String.t(),
              description: String.t(),
              config_files: [String.t()],
              query_language: String.t() | nil
            }
end
