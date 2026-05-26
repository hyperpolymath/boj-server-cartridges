# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolySSG.LSP.Handlers.Diagnostics do
  @moduledoc """
  Provides diagnostics for SSG projects.

  Parses build output and extracts:
  - Build errors (missing files, syntax errors)
  - Configuration issues (invalid TOML/YAML)
  - Template syntax errors
  - Missing frontmatter fields
  """

  require Logger

  @doc """
  Handle diagnostics request by running build and parsing output.

  Returns LSP diagnostics format:
  ```
  %{
    "uri" => "file:///path/to/file.md",
    "diagnostics" => [
      %{
        "range" => %{"start" => %{"line" => 0, "character" => 0}, ...},
        "severity" => 1,  # 1=Error, 2=Warning, 3=Info, 4=Hint
        "source" => "poly-ssg",
        "message" => "Template not found: base.html"
      }
    ]
  }
  ```
  """
  def handle(params, %{project_path: project_path, detected_ssg: ssg}) when project_path != nil do
    uri = get_in(params, ["textDocument", "uri"]) || "file://#{project_path}"

    diagnostics =
      case run_build(project_path, ssg) do
        {:ok, _output} ->
          # Build succeeded - no diagnostics
          []

        {:error, error_output} ->
          # Parse errors from build output
          parse_errors(error_output, ssg)
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

  # Run build for diagnostics (don't output to disk)
  defp run_build(project_path, :zola) do
    case System.cmd("zola", ["check"], cd: project_path, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {error, _} -> {:error, error}
    end
  rescue
    e -> {:error, "Zola not found: #{inspect(e)}"}
  end

  defp run_build(project_path, :hakyll) do
    site_bin = Path.join(project_path, "site")

    if File.exists?(site_bin) do
      case System.cmd(site_bin, ["check"], cd: project_path, stderr_to_stdout: true) do
        {output, 0} -> {:ok, output}
        {error, _} -> {:error, error}
      end
    else
      {:error, "site binary not found. Run 'cabal build' first."}
    end
  rescue
    e -> {:error, "Hakyll check failed: #{inspect(e)}"}
  end

  defp run_build(project_path, :franklin) do
    # Franklin doesn't have a check command, try parse config
    config_path = Path.join(project_path, "config.md")

    case File.read(config_path) do
      {:ok, content} ->
        # Basic validation - check for common syntax errors
        if String.contains?(content, "@def") do
          {:ok, "Config valid"}
        else
          {:error, "config.md missing @def declarations"}
        end

      {:error, reason} ->
        {:error, "Cannot read config.md: #{inspect(reason)}"}
    end
  end

  defp run_build(_project_path, _ssg) do
    {:ok, "No diagnostics available for this SSG"}
  end

  # Parse error messages from build output
  defp parse_errors(output, ssg) do
    output
    |> String.split("\n")
    |> Enum.flat_map(&parse_error_line(&1, ssg))
    |> Enum.take(50)  # Limit to 50 diagnostics
  end

  # Zola error format: "Error: ..."
  defp parse_error_line("Error: " <> message, :zola) do
    [create_diagnostic(message, 1)]
  end

  defp parse_error_line("Warning: " <> message, :zola) do
    [create_diagnostic(message, 2)]
  end

  # Hakyll error format: varies, look for common patterns
  defp parse_error_line(line, :hakyll) do
    cond do
      String.contains?(line, "error:") ->
        [create_diagnostic(line, 1)]

      String.contains?(line, "warning:") ->
        [create_diagnostic(line, 2)]

      true ->
        []
    end
  end

  # Franklin error format
  defp parse_error_line(line, :franklin) do
    cond do
      String.contains?(line, "ERROR") ->
        [create_diagnostic(line, 1)]

      String.contains?(line, "WARNING") ->
        [create_diagnostic(line, 2)]

      true ->
        []
    end
  end

  defp parse_error_line(_line, _ssg), do: []

  # Create a diagnostic entry
  defp create_diagnostic(message, severity) do
    %{
      "range" => %{
        "start" => %{"line" => 0, "character" => 0},
        "end" => %{"line" => 0, "character" => 100}
      },
      "severity" => severity,
      "source" => "poly-ssg",
      "message" => String.trim(message)
    }
  end
end
