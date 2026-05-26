# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyOrchestrator.LSP.Server do
  @moduledoc """
  Main LSP server for poly-orchestrator.

  Provides LSP features for stack.compose.toml files:
  - Completion: Component types, LSP server names, security policies
  - Diagnostics: Stack validation, dependency cycles, security issues
  - Hover: Component documentation, execution estimates
  - Code Actions: Quick fixes, template insertions
  - Commands: Execute stack, validate stack, rollback execution
  """

  use GenLSP

  alias PolyOrchestrator.Orchestrator.{StackParser, Planner, Executor}
  alias PolyOrchestrator.LSP.Handlers

  def start_link(args) do
    GenLSP.start_link(__MODULE__, args, [])
  end

  @impl true
  def init(lsp, _args) do
    {:ok, assign(lsp, documents: %{})}
  end

  @impl true
  def handle_request(
        %{method: "initialize", params: %{"capabilities" => _capabilities}},
        lsp
      ) do
    server_capabilities = %{
      "textDocumentSync" => %{
        "openClose" => true,
        "change" => 1,  # Full sync
        "save" => true
      },
      "completionProvider" => %{
        "triggerCharacters" => [".", "[", "\""]
      },
      "hoverProvider" => true,
      "diagnosticProvider" => %{
        "interFileDependencies" => false,
        "workspaceDiagnostics" => false
      },
      "executeCommandProvider" => %{
        "commands" => [
          "polyOrchestrator.executeStack",
          "polyOrchestrator.validateStack",
          "polyOrchestrator.rollbackExecution",
          "polyOrchestrator.estimateDuration"
        ]
      }
    }

    {:reply, %{"capabilities" => server_capabilities}, lsp}
  end

  @impl true
  def handle_notification(
        %{method: "textDocument/didOpen", params: params},
        lsp
      ) do
    uri = params["textDocument"]["uri"]
    text = params["textDocument"]["text"]

    # Store document
    lsp = update_document(lsp, uri, text)

    # Send diagnostics
    diagnostics = Handlers.Diagnostics.analyze(text)
    send_diagnostics(lsp, uri, diagnostics)

    {:noreply, lsp}
  end

  @impl true
  def handle_notification(
        %{method: "textDocument/didChange", params: params},
        lsp
      ) do
    uri = params["textDocument"]["uri"]
    changes = params["contentChanges"]

    # Get latest text (full sync)
    text = List.last(changes)["text"]

    # Update document
    lsp = update_document(lsp, uri, text)

    # Send diagnostics
    diagnostics = Handlers.Diagnostics.analyze(text)
    send_diagnostics(lsp, uri, diagnostics)

    {:noreply, lsp}
  end

  @impl true
  def handle_notification(%{method: "textDocument/didSave", params: params}, lsp) do
    uri = params["textDocument"]["uri"]

    # Re-validate on save
    case get_document(lsp, uri) do
      nil ->
        {:noreply, lsp}

      text ->
        diagnostics = Handlers.Diagnostics.analyze(text)
        send_diagnostics(lsp, uri, diagnostics)
        {:noreply, lsp}
    end
  end

  @impl true
  def handle_request(
        %{method: "textDocument/completion", params: params},
        lsp
      ) do
    uri = params["textDocument"]["uri"]
    position = params["position"]

    text = get_document(lsp, uri) || ""
    completions = Handlers.Completion.provide(text, position)

    {:reply, %{"items" => completions}, lsp}
  end

  @impl true
  def handle_request(
        %{method: "textDocument/hover", params: params},
        lsp
      ) do
    uri = params["textDocument"]["uri"]
    position = params["position"]

    text = get_document(lsp, uri) || ""

    case Handlers.Hover.provide(text, position) do
      nil ->
        {:reply, nil, lsp}

      hover_content ->
        {:reply, %{"contents" => hover_content}, lsp}
    end
  end

  @impl true
  def handle_request(
        %{method: "workspace/executeCommand", params: params},
        lsp
      ) do
    command = params["command"]
    arguments = params["arguments"] || []

    result = execute_command(command, arguments)

    {:reply, result, lsp}
  end

  # Private Functions

  defp update_document(lsp, uri, text) do
    documents = Map.put(lsp.assigns.documents, uri, text)
    assign(lsp, documents: documents)
  end

  defp get_document(lsp, uri) do
    Map.get(lsp.assigns.documents, uri)
  end

  defp send_diagnostics(lsp, uri, diagnostics) do
    notification = %{
      method: "textDocument/publishDiagnostics",
      params: %{
        uri: uri,
        diagnostics: diagnostics
      }
    }

    GenLSP.send_notification(lsp, notification)
  end

  defp execute_command("polyOrchestrator.executeStack", [uri]) do
    # Parse and execute stack
    case StackParser.parse_file(uri) do
      {:ok, stack} ->
        case Planner.build_plan(stack) do
          {:ok, plan} ->
            case Executor.execute(plan) do
              {:ok, result} ->
                %{success: true, result: result}

              {:error, reason} ->
                %{success: false, error: inspect(reason)}
            end

          {:error, reason} ->
            %{success: false, error: "Planning failed: #{inspect(reason)}"}
        end

      {:error, reason} ->
        %{success: false, error: "Parse failed: #{inspect(reason)}"}
    end
  end

  defp execute_command("polyOrchestrator.validateStack", [uri]) do
    case StackParser.parse_file(uri) do
      {:ok, stack} ->
        case Planner.build_plan(stack) do
          {:ok, _plan} ->
            %{valid: true}

          {:error, reason} ->
            %{valid: false, errors: [inspect(reason)]}
        end

      {:error, reason} ->
        %{valid: false, errors: [inspect(reason)]}
    end
  end

  defp execute_command("polyOrchestrator.estimateDuration", [uri]) do
    with {:ok, stack} <- StackParser.parse_file(uri),
         {:ok, plan} <- Planner.build_plan(stack) do
      estimate = Planner.estimate_duration(plan)
      %{success: true, estimate: estimate}
    else
      {:error, reason} ->
        %{success: false, error: inspect(reason)}
    end
  end

  defp execute_command("polyOrchestrator.rollbackExecution", [execution_id]) do
    case Executor.rollback(execution_id) do
      {:ok, _} ->
        %{success: true}

      {:error, reason} ->
        %{success: false, error: inspect(reason)}
    end
  end

  defp execute_command(unknown, _args) do
    %{success: false, error: "Unknown command: #{unknown}"}
  end
end
