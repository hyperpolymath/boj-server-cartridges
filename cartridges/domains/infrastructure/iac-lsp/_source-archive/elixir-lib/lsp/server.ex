# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyIaC.LSP.Server do
  @moduledoc """
  GenLSP server implementation for PolyIaC.

  Handles LSP protocol messages and delegates to appropriate handlers.
  """
  use GenLSP

  require Logger

  alias PolyIaC.LSP.Handlers.{Completion, Diagnostics, Hover}

  @impl GenLSP
  def handle_info(_msg, lsp), do: {:noreply, lsp}

  def start_link(args) do
    GenLSP.start_link(__MODULE__, args, [])
  end

  @impl GenLSP
  def init(_lsp, _args) do
    {:ok, %{project_path: nil, detected_iac: nil, documents: %{}}}
  end

  @impl GenLSP
  def handle_request(%{"method" => "initialize", "params" => params}, lsp) do
    project_path = get_in(params, ["rootUri"]) |> parse_uri()

    Logger.info("Initializing LSP for project: #{inspect(project_path)}")

    # Auto-detect IaC type
    detected_iac = detect_iac(project_path)

    Logger.info("Detected IaC: #{inspect(detected_iac)}")

    server_capabilities = %{
      "textDocumentSync" => %{
        "openClose" => true,
        "change" => 1,  # Full sync
        "save" => %{"includeText" => false}
      },
      "completionProvider" => %{
        "triggerCharacters" => [".", ":", "{", "["],
        "resolveProvider" => false
      },
      "hoverProvider" => true,
      "executeCommandProvider" => %{
        "commands" => ["poly-iac.validate", "poly-iac.plan", "poly-iac.format"]
      }
    }

    result = %{
      "capabilities" => server_capabilities,
      "serverInfo" => %{
        "name" => "PolyIaC LSP",
        "version" => PolyIaC.LSP.version()
      }
    }

    new_state = Map.merge(lsp, %{project_path: project_path, detected_iac: detected_iac})
    {:reply, result, new_state}
  end

  @impl GenLSP
  def handle_request(%{"method" => "textDocument/completion", "params" => params}, lsp) do
    completions = Completion.handle(params, lsp.assigns)
    {:reply, completions, lsp}
  end

  @impl GenLSP
  def handle_request(%{"method" => "textDocument/hover", "params" => params}, lsp) do
    hover_info = Hover.handle(params, lsp.assigns)
    {:reply, hover_info, lsp}
  end

  @impl GenLSP
  def handle_request(%{"method" => "workspace/executeCommand", "params" => params}, lsp) do
    command = params["command"]
    args = params["arguments"] || []
    result = execute_command(command, args, lsp.assigns)
    {:reply, result, lsp}
  end

  @impl GenLSP
  def handle_request(_request, lsp) do
    {:reply, nil, lsp}
  end

  @impl GenLSP
  def handle_notification(%{"method" => "initialized"}, lsp) do
    Logger.info("LSP server initialized")
    {:noreply, lsp}
  end

  @impl GenLSP
  def handle_notification(%{"method" => "textDocument/didOpen", "params" => params}, lsp) do
    uri = params["textDocument"]["uri"]
    text = params["textDocument"]["text"]
    version = params["textDocument"]["version"]

    Logger.info("Document opened: #{uri}")

    # Store document state
    documents = Map.put(lsp.assigns.documents, uri, %{text: text, version: version})
    new_state = put_in(lsp.assigns.documents, documents)

    # Trigger diagnostics on open
    spawn(fn ->
      diagnostics = Diagnostics.handle(params, new_state.assigns)

      GenLSP.notify(lsp, %{
        "method" => "textDocument/publishDiagnostics",
        "params" => diagnostics
      })
    end)

    {:noreply, new_state}
  end

  @impl GenLSP
  def handle_notification(%{"method" => "textDocument/didChange", "params" => params}, lsp) do
    uri = params["textDocument"]["uri"]
    changes = params["contentChanges"]
    version = params["textDocument"]["version"]

    # Update document with full sync (change type 1)
    new_text = List.first(changes)["text"]
    documents = Map.update(lsp.assigns.documents, uri, %{text: new_text, version: version}, fn doc ->
      %{doc | text: new_text, version: version}
    end)

    new_state = put_in(lsp.assigns.documents, documents)
    {:noreply, new_state}
  end

  @impl GenLSP
  def handle_notification(%{"method" => "textDocument/didClose", "params" => params}, lsp) do
    uri = params["textDocument"]["uri"]
    Logger.info("Document closed: #{uri}")

    # Remove document from state
    documents = Map.delete(lsp.assigns.documents, uri)
    new_state = put_in(lsp.assigns.documents, documents)

    {:noreply, new_state}
  end

  @impl GenLSP
  def handle_notification(%{"method" => "textDocument/didSave", "params" => params}, lsp) do
    uri = params["textDocument"]["uri"]
    Logger.info("File saved: #{uri}")

    # Trigger diagnostics on save
    spawn(fn ->
      diagnostics = Diagnostics.handle(params, lsp.assigns)

      GenLSP.notify(lsp, %{
        "method" => "textDocument/publishDiagnostics",
        "params" => diagnostics
      })
    end)

    {:noreply, lsp}
  end

  @impl GenLSP
  def handle_notification(_notification, lsp), do: {:noreply, lsp}

  # Private helpers

  defp parse_uri(nil), do: nil
  defp parse_uri(uri) when is_binary(uri) do
    case URI.parse(uri) do
      %URI{scheme: "file", path: path} -> path
      _ -> nil
    end
  end

  defp detect_iac(nil), do: nil
  defp detect_iac(project_path) do
    adapters = [
      {PolyIaC.Adapters.OpenTofu, :opentofu},
      {PolyIaC.Adapters.Pulumi, :pulumi}
    ]

    Enum.find_value(adapters, fn {adapter, name} ->
      case adapter.detect(project_path) do
        {:ok, true} -> name
        _ -> nil
      end
    end)
  end

  defp execute_command("poly-iac.validate", _args, %{project_path: path, detected_iac: iac}) when path != nil do
    case iac do
      :opentofu -> PolyIaC.Adapters.OpenTofu.validate(path, [])
      :pulumi -> PolyIaC.Adapters.Pulumi.validate(path, [])
      _ -> {:error, "No IaC tool detected"}
    end
  end

  defp execute_command("poly-iac.plan", _args, %{project_path: path, detected_iac: iac}) when path != nil do
    case iac do
      :opentofu -> PolyIaC.Adapters.OpenTofu.plan(path, [])
      :pulumi -> PolyIaC.Adapters.Pulumi.preview(path, [])
      _ -> {:error, "No IaC tool detected"}
    end
  end

  defp execute_command("poly-iac.format", _args, %{project_path: path, detected_iac: iac}) when path != nil do
    case iac do
      :opentofu -> PolyIaC.Adapters.OpenTofu.format(path, [])
      :pulumi -> {:ok, "Pulumi uses language-specific formatters"}
      _ -> {:error, "No IaC tool detected"}
    end
  end

  defp execute_command(_command, _args, _assigns) do
    {:error, "Unknown command or no project detected"}
  end
end
