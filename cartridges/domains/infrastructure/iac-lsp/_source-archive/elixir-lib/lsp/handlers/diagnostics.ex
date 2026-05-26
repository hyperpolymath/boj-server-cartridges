# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyIaC.LSP.Handlers.Diagnostics do
  @moduledoc """
  Provides diagnostics for Infrastructure as Code projects.

  Validates:
  - OpenTofu/Terraform configuration syntax
  - Pulumi program structure
  - Resource dependencies
  - Configuration errors
  """

  require Logger

  @doc """
  Handle diagnostics request by running validation and parsing output.

  Returns LSP diagnostics format.
  """
  def handle(params, %{project_path: project_path, detected_iac: iac}) when project_path != nil do
    uri = get_in(params, ["textDocument", "uri"]) || "file://#{project_path}"

    diagnostics =
      case run_validation(project_path, iac) do
        {:ok, _output} ->
          # Validation succeeded - no diagnostics
          []

        {:error, error_output} ->
          # Parse errors from validation output
          parse_errors(error_output, iac)
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
  defp run_validation(project_path, :opentofu) do
    case System.cmd("tofu", ["validate"], cd: project_path, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {error, _} -> {:error, error}
    end
  rescue
    e -> {:error, "OpenTofu not found: #{inspect(e)}"}
  end

  defp run_validation(project_path, :pulumi) do
    case System.cmd("pulumi", ["preview", "--non-interactive"], cd: project_path, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {error, _} -> {:error, error}
    end
  rescue
    e -> {:error, "Pulumi not found: #{inspect(e)}"}
  end

  defp run_validation(_project_path, _iac) do
    {:ok, "No validation available for this IaC tool"}
  end

  # Parse error messages from validation output
  defp parse_errors(output, iac) do
    output
    |> String.split("\n")
    |> Enum.flat_map(&parse_error_line(&1, iac))
    |> Enum.take(50)  # Limit to 50 diagnostics
  end

  # OpenTofu/Terraform error format
  defp parse_error_line("Error: " <> message, :opentofu) do
    [create_diagnostic(message, 1)]
  end

  defp parse_error_line("Warning: " <> message, :opentofu) do
    [create_diagnostic(message, 2)]
  end

  # Pulumi error format
  defp parse_error_line(line, :pulumi) do
    cond do
      String.contains?(line, "error:") ->
        [create_diagnostic(line, 1)]

      String.contains?(line, "warning:") ->
        [create_diagnostic(line, 2)]

      true ->
        []
    end
  end

  defp parse_error_line(_line, _iac), do: []

  # Create a diagnostic entry
  defp create_diagnostic(message, severity) do
    %{
      "range" => %{
        "start" => %{"line" => 0, "character" => 0},
        "end" => %{"line" => 0, "character" => 100}
      },
      "severity" => severity,
      "source" => "poly-iac",
      "message" => String.trim(message)
    }
  end
end
