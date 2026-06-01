# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyOrchestrator.LSP.Handlers.Diagnostics do
  @moduledoc """
  Diagnostics provider for stack.compose.toml validation.
  """

  alias PolyOrchestrator.Orchestrator.{StackParser, Planner}

  def analyze(text) do
    case StackParser.parse_string(text) do
      {:ok, stack} ->
        validate_stack(stack)

      {:error, reason} ->
        [
          %{
            range: %{
              start: %{line: 0, character: 0},
              end: %{line: 0, character: 100}
            },
            severity: 1,  # Error
            message: "Parse error: #{inspect(reason)}",
            source: "poly-orchestrator"
          }
        ]
    end
  end

  defp validate_stack(stack) do
    diagnostics = []

    # Check for dependency cycles
    diagnostics =
      case StackParser.extract_dependency_graph(stack) do
        {:ok, graph} ->
          case Planner.validate_graph(graph) do
            :ok ->
              diagnostics

            {:error, reason} ->
              [
                %{
                  range: %{start: %{line: 0, character: 0}, end: %{line: 0, character: 100}},
                  severity: 1,
                  message: "Dependency cycle: #{reason}",
                  source: "poly-orchestrator"
                }
                | diagnostics
              ]
          end

        {:error, _} ->
          diagnostics
      end

    # Check for missing LSP servers
    diagnostics = diagnostics ++ check_lsp_servers(stack)

    # Check for security issues
    diagnostics = diagnostics ++ check_security(stack)

    diagnostics
  end

  defp check_lsp_servers(stack) do
    valid_servers = [
      "poly-cloud",
      "poly-db",
      "poly-container",
      "poly-k8s",
      "poly-observability",
      "poly-secret",
      "poly-git",
      "poly-queue",
      "poly-ssg",
      "poly-iac",
      "claude-firefox",
      "poly-proof"
    ]

    components = stack["components"] || []

    Enum.flat_map(components, fn component ->
      lsp_server = component["lsp_server"]

      if lsp_server not in valid_servers do
        [
          %{
            range: %{start: %{line: 0, character: 0}, end: %{line: 0, character: 100}},
            severity: 1,
            message: "Unknown LSP server: #{lsp_server}",
            source: "poly-orchestrator"
          }
        ]
      else
        []
      end
    end)
  end

  defp check_security(stack) do
    security = stack["security"] || %{}

    cond do
      !security["validated"] ->
        [
          %{
            range: %{start: %{line: 0, character: 0}, end: %{line: 0, character: 100}},
            severity: 2,  # Warning
            message: "Security policies not validated by miniKanren",
            source: "poly-orchestrator"
          }
        ]

      is_nil(security["threat_model"]) ->
        [
          %{
            range: %{start: %{line: 0, character: 0}, end: %{line: 0, character: 100}},
            severity: 2,
            message: "No threat model specified",
            source: "poly-orchestrator"
          }
        ]

      true ->
        []
    end
  end
end
