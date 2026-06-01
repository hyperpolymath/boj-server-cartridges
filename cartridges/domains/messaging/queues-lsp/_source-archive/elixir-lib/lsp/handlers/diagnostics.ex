# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyQueue.LSP.Handlers.Diagnostics do
  @moduledoc """
  Provides diagnostics for message queue configurations.

  Validates:
  - Redis configuration syntax
  - RabbitMQ configuration files
  - NATS configuration files
  - Connection parameters
  """

  require Logger

  @doc """
  Handle diagnostics request by running validation and parsing output.

  Returns LSP diagnostics format.
  """
  def handle(params, %{project_path: project_path, detected_queue: queue}) when project_path != nil do
    uri = get_in(params, ["textDocument", "uri"]) || "file://#{project_path}"

    diagnostics =
      case run_validation(project_path, queue, uri) do
        {:ok, _output} ->
          # Validation succeeded - no diagnostics
          []

        {:error, error_output} ->
          # Parse errors from validation output
          parse_errors(error_output, queue)
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

  # Run validation for diagnostics
  defp run_validation(project_path, :redis_streams, uri) do
    # Redis config validation
    if String.contains?(uri, "redis.conf") do
      file_path = URI.parse(uri).path

      case File.read(file_path) do
        {:ok, content} ->
          # Basic syntax validation
          validate_redis_config(content)

        {:error, reason} ->
          {:error, "Cannot read file: #{inspect(reason)}"}
      end
    else
      {:ok, "No Redis configuration file"}
    end
  end

  defp run_validation(project_path, :rabbitmq, uri) do
    # RabbitMQ config validation
    if String.ends_with?(uri, ".conf") do
      file_path = URI.parse(uri).path

      case File.read(file_path) do
        {:ok, content} ->
          validate_rabbitmq_config(content)

        {:error, reason} ->
          {:error, "Cannot read file: #{inspect(reason)}"}
      end
    else
      {:ok, "No RabbitMQ configuration file"}
    end
  end

  defp run_validation(project_path, :nats, uri) do
    # NATS config validation
    if String.ends_with?(uri, ".conf") do
      file_path = URI.parse(uri).path

      case File.read(file_path) do
        {:ok, content} ->
          validate_nats_config(content)

        {:error, reason} ->
          {:error, "Cannot read file: #{inspect(reason)}"}
      end
    else
      {:ok, "No NATS configuration file"}
    end
  end

  defp run_validation(_project_path, _queue, _uri) do
    {:ok, "No validation available for this queue system"}
  end

  # Redis config validation
  defp validate_redis_config(content) do
    errors = []

    # Check for common misconfigurations
    errors = if String.contains?(content, "bind 0.0.0.0") and not String.contains?(content, "requirepass") do
      ["WARNING: bind 0.0.0.0 without requirepass is insecure" | errors]
    else
      errors
    end

    if Enum.empty?(errors) do
      {:ok, "Valid Redis configuration"}
    else
      {:error, Enum.join(errors, "\n")}
    end
  end

  # RabbitMQ config validation
  defp validate_rabbitmq_config(content) do
    # Basic validation - check for syntax errors
    lines = String.split(content, "\n")

    errors = Enum.reduce(lines, [], fn line, acc ->
      trimmed = String.trim(line)

      cond do
        String.starts_with?(trimmed, "#") or trimmed == "" ->
          acc

        not String.contains?(trimmed, "=") and not String.contains?(trimmed, "{") ->
          ["Invalid syntax: #{line}" | acc]

        true ->
          acc
      end
    end)

    if Enum.empty?(errors) do
      {:ok, "Valid RabbitMQ configuration"}
    else
      {:error, Enum.join(Enum.reverse(errors), "\n")}
    end
  end

  # NATS config validation
  defp validate_nats_config(content) do
    # Check for required sections
    errors = []

    errors = if not String.contains?(content, "port") do
      ["Missing 'port' configuration" | errors]
    else
      errors
    end

    if Enum.empty?(errors) do
      {:ok, "Valid NATS configuration"}
    else
      {:error, Enum.join(errors, "\n")}
    end
  end

  # Parse error messages from validation output
  defp parse_errors(output, _queue) do
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
      String.contains?(line, "Invalid") or String.contains?(line, "Missing") ->
        [create_diagnostic(line, 1)]

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
      "source" => "poly-queue",
      "message" => String.trim(message)
    }
  end
end
