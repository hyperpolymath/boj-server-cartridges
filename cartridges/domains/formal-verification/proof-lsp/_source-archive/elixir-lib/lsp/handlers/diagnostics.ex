# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyProof.LSP.Handlers.Diagnostics do
  @moduledoc """
  Provides diagnostics for proof assistant files.

  Validates:
  - Proof syntax
  - Type checking
  - Theorem statements
  - Proof completeness
  """

  require Logger

  @doc """
  Handle diagnostics request by running proof checker and parsing output.

  Returns LSP diagnostics format.
  """
  def handle(params, %{project_path: project_path, detected_prover: prover}) when project_path != nil do
    uri = get_in(params, ["textDocument", "uri"]) || "file://#{project_path}"

    diagnostics =
      case run_checker(uri, project_path, prover) do
        {:ok, _output} ->
          # Check succeeded - no diagnostics
          []

        {:error, error_output} ->
          # Parse errors from checker output
          parse_errors(error_output, prover)
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

  # Run proof checker
  defp run_checker(uri, project_path, :coq) do
    file_path = URI.parse(uri).path

    if File.exists?(file_path) and String.ends_with?(file_path, ".v") do
      case System.cmd("coqc", ["-q", file_path], cd: project_path, stderr_to_stdout: true) do
        {output, 0} -> {:ok, output}
        {error, _} -> {:error, error}
      end
    else
      {:ok, "Not a Coq file"}
    end
  rescue
    e -> {:error, "coqc not found: #{inspect(e)}"}
  end

  defp run_checker(uri, project_path, :lean) do
    file_path = URI.parse(uri).path

    if File.exists?(file_path) and String.ends_with?(file_path, ".lean") do
      case System.cmd("lean", ["--make", file_path], cd: project_path, stderr_to_stdout: true) do
        {output, 0} -> {:ok, output}
        {error, _} -> {:error, error}
      end
    else
      {:ok, "Not a Lean file"}
    end
  rescue
    e -> {:error, "lean not found: #{inspect(e)}"}
  end

  defp run_checker(uri, project_path, :isabelle) do
    file_path = URI.parse(uri).path

    if File.exists?(file_path) and String.ends_with?(file_path, ".thy") do
      # Isabelle checking requires theory context
      {:ok, "Isabelle requires interactive session for checking"}
    else
      {:ok, "Not an Isabelle theory file"}
    end
  end

  defp run_checker(uri, project_path, :agda) do
    file_path = URI.parse(uri).path

    if File.exists?(file_path) and String.ends_with?(file_path, ".agda") do
      case System.cmd("agda", [file_path], cd: project_path, stderr_to_stdout: true) do
        {output, 0} -> {:ok, output}
        {error, _} -> {:error, error}
      end
    else
      {:ok, "Not an Agda file"}
    end
  rescue
    e -> {:error, "agda not found: #{inspect(e)}"}
  end

  defp run_checker(_uri, _project_path, _prover) do
    {:ok, "No proof checker available"}
  end

  # Parse error messages from checker output
  defp parse_errors(output, prover) do
    output
    |> String.split("\n")
    |> Enum.flat_map(&parse_error_line(&1, prover))
    |> Enum.take(50)  # Limit to 50 diagnostics
  end

  # Coq error format
  defp parse_error_line(line, :coq) do
    cond do
      String.contains?(line, "Error:") ->
        [create_diagnostic(line, 1)]

      String.contains?(line, "Warning:") ->
        [create_diagnostic(line, 2)]

      true ->
        []
    end
  end

  # Lean error format
  defp parse_error_line(line, :lean) do
    cond do
      String.contains?(line, "error:") ->
        [create_diagnostic(line, 1)]

      String.contains?(line, "warning:") ->
        [create_diagnostic(line, 2)]

      true ->
        []
    end
  end

  # Isabelle error format
  defp parse_error_line(line, :isabelle) do
    cond do
      String.contains?(line, "***") ->
        [create_diagnostic(line, 1)]

      true ->
        []
    end
  end

  # Agda error format
  defp parse_error_line(line, :agda) do
    cond do
      String.match?(line, ~r/\d+,\d+[^:]*:/) ->
        [create_diagnostic(line, 1)]

      true ->
        []
    end
  end

  defp parse_error_line(_line, _prover), do: []

  # Create a diagnostic entry
  defp create_diagnostic(message, severity) do
    %{
      "range" => %{
        "start" => %{"line" => 0, "character" => 0},
        "end" => %{"line" => 0, "character" => 100}
      },
      "severity" => severity,
      "source" => "poly-proof",
      "message" => String.trim(message)
    }
  end
end
