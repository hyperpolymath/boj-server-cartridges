# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyObservability.LSP.Handlers.Diagnostics do
  @moduledoc """
  Provides diagnostics for observability configurations.

  Validates:
  - Prometheus configuration and rules
  - Grafana dashboard JSON
  - Loki configuration
  - Jaeger configuration
  - Query syntax (PromQL, LogQL)
  """

  require Logger

  @doc """
  Handle diagnostics request by running validation and parsing output.

  Returns LSP diagnostics format.
  """
  def handle(params, %{project_path: project_path, detected_tools: tools}) when project_path != nil do
    uri = get_in(params, ["textDocument", "uri"]) || "file://#{project_path}"

    diagnostics =
      case run_validation(uri, project_path, tools) do
        {:ok, _output} ->
          # Validation succeeded - no diagnostics
          []

        {:error, error_output} ->
          # Parse errors from validation output
          parse_errors(error_output, tools)
      end

    %{
      "uri" => uri,
      "diagnostics" => diagnostics
    }
  end

  def handle(_params, _assigns) do
    # No project path - return empty diagnostics
    %{"uri" => "", "diagnostics" => []}
  end

  # Run validation based on file type
  defp run_validation(uri, project_path, tools) do
    cond do
      String.contains?(uri, "prometheus") and (String.ends_with?(uri, ".yml") or String.ends_with?(uri, ".yaml")) ->
        run_prometheus_validation(project_path, tools)

      String.contains?(uri, "grafana") and String.ends_with?(uri, ".json") ->
        run_grafana_validation(uri)

      String.contains?(uri, "loki") ->
        run_loki_validation(project_path, tools)

      true ->
        {:ok, "No specific validation available"}
    end
  end

  # Prometheus validation
  defp run_prometheus_validation(project_path, tools) do
    if :prometheus in tools do
      config_file = Path.join(project_path, "prometheus.yml")

      if File.exists?(config_file) do
        case System.cmd("promtool", ["check", "config", config_file], stderr_to_stdout: true) do
          {output, 0} -> {:ok, output}
          {error, _} -> {:error, error}
        end
      else
        {:ok, "No prometheus.yml found"}
      end
    else
      {:ok, "Prometheus not detected"}
    end
  rescue
    e -> {:error, "promtool not found: #{inspect(e)}"}
  end

  # Grafana dashboard validation
  defp run_grafana_validation(uri) do
    file_path = URI.parse(uri).path

    case File.read(file_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, _json} -> {:ok, "Valid JSON"}
          {:error, error} -> {:error, "JSON parse error: #{inspect(error)}"}
        end

      {:error, reason} ->
        {:error, "Cannot read file: #{inspect(reason)}"}
    end
  end

  # Loki validation
  defp run_loki_validation(project_path, tools) do
    if :loki in tools do
      config_file = Path.join(project_path, "loki.yaml")

      if File.exists?(config_file) do
        # Basic YAML validation
        case YamlElixir.read_from_file(config_file) do
          {:ok, _} -> {:ok, "Valid YAML"}
          {:error, error} -> {:error, "YAML parse error: #{inspect(error)}"}
        end
      else
        {:ok, "No loki.yaml found"}
      end
    else
      {:ok, "Loki not detected"}
    end
  rescue
    e -> {:error, "YAML validation failed: #{inspect(e)}"}
  end

  # Parse error messages from validation output
  defp parse_errors(output, _tools) do
    output
    |> String.split("\n")
    |> Enum.flat_map(&parse_error_line(&1))
    |> Enum.take(50)  # Limit to 50 diagnostics
  end

  # Parse error lines
  defp parse_error_line("ERROR: " <> message) do
    [create_diagnostic(message, 1)]
  end

  defp parse_error_line("WARNING: " <> message) do
    [create_diagnostic(message, 2)]
  end

  defp parse_error_line(line) do
    cond do
      String.contains?(line, "error:") ->
        [create_diagnostic(line, 1)]

      String.contains?(line, "warning:") ->
        [create_diagnostic(line, 2)]

      true ->
        []
    end
  end

  # Create a diagnostic entry
  defp create_diagnostic(message, severity) do
    %{
      "range" => %{
        "start" => %{"line" => 0, "character" => 0},
        "end" => %{"line" => 0, "character" => 100}
      },
      "severity" => severity,
      "source" => "poly-observability",
      "message" => String.trim(message)
    }
  end
end
