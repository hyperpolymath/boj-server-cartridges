# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyCloud.LSP.Server do
  @moduledoc """
  LSP server implementation for PolyCloud.

  Handles LSP protocol messages and delegates to cloud provider adapters.
  """
  use GenLSP

  require Logger

  alias PolyCloud.Adapters
  alias PolyCloud.LSP.Handlers.{Completion, Diagnostics, Hover}

  def start_link(args) do
    GenLSP.start_link(__MODULE__, args, [])
  end

  @impl true
  def init(_lsp, args) do
    {:ok, %{project_path: args[:project_path] || File.cwd!(), documents: %{}, detected_provider: nil}}
  end

  @impl true
  def handle_request(%GenLSP.Requests.Initialize{params: params}, _from, state) do
    root_uri = params.root_uri || params.root_path
    project_path = if root_uri, do: URI.parse(root_uri).path, else: state.project_path

    capabilities = %GenLSP.Structures.ServerCapabilities{
      text_document_sync: %GenLSP.Structures.TextDocumentSyncOptions{
        open_close: true,
        change: GenLSP.Enumerations.TextDocumentSyncKind.full(),
        save: %GenLSP.Structures.SaveOptions{include_text: false}
      },
      completion_provider: %GenLSP.Structures.CompletionOptions{
        trigger_characters: [".", ":", "-"],
        resolve_provider: false
      },
      hover_provider: true,
      execute_command_provider: %GenLSP.Structures.ExecuteCommandOptions{
        commands: [
          "polycloud.deploy",
          "polycloud.status",
          "polycloud.logs",
          "polycloud.configure"
        ]
      }
    }

    result = %GenLSP.Structures.InitializeResult{
      capabilities: capabilities,
      server_info: %GenLSP.Structures.ServerInfo{
        name: "PolyCloud LSP",
        version: "0.1.0"
      }
    }

    {:reply, result, %{state | project_path: project_path}}
  end

  @impl true
  def handle_request(%GenLSP.Requests.Completion{params: params}, _from, state) do
    completions = Completion.handle(params, state)
    {:reply, completions, state}
  end

  @impl true
  def handle_request(%GenLSP.Requests.Hover{params: params}, _from, state) do
    hover_info = Hover.handle(params, state)
    {:reply, hover_info, state}
  end

  @impl true
  def handle_request(%GenLSP.Requests.ExecuteCommand{params: params}, _from, state) do
    command = params.command
    args = params.arguments || []

    result =
      case command do
        "polycloud.deploy" ->
          handle_deploy(args, state)

        "polycloud.status" ->
          handle_status(args, state)

        "polycloud.logs" ->
          handle_logs(args, state)

        "polycloud.configure" ->
          handle_configure(args, state)

        _ ->
          {:error, "Unknown command: #{command}"}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_request(%GenLSP.Requests.Shutdown{}, _from, state) do
    {:reply, nil, state}
  end

  @impl true
  def handle_notification(%GenLSP.Notifications.TextDocumentDidOpen{params: params}, state) do
    uri = params.text_document.uri
    text = params.text_document.text
    version = params.text_document.version

    Logger.info("Document opened: #{uri}")

    documents = Map.put(state.documents, uri, %{text: text, version: version})
    new_state = %{state | documents: documents}

    # Trigger diagnostics
    spawn(fn ->
      diagnostics = Diagnostics.handle(%{"textDocument" => %{"uri" => uri}}, new_state)
      GenLSP.notify(self(), %{
        "method" => "textDocument/publishDiagnostics",
        "params" => diagnostics
      })
    end)

    {:noreply, new_state}
  end

  @impl true
  def handle_notification(%GenLSP.Notifications.TextDocumentDidChange{params: params}, state) do
    uri = params.text_document.uri
    changes = params.content_changes
    version = params.text_document.version

    new_text = List.first(changes).text
    documents = Map.update(state.documents, uri, %{text: new_text, version: version}, fn doc ->
      %{doc | text: new_text, version: version}
    end)

    {:noreply, %{state | documents: documents}}
  end

  @impl true
  def handle_notification(%GenLSP.Notifications.TextDocumentDidClose{params: params}, state) do
    uri = params.text_document.uri
    Logger.info("Document closed: #{uri}")

    documents = Map.delete(state.documents, uri)
    {:noreply, %{state | documents: documents}}
  end

  @impl true
  def handle_notification(%GenLSP.Notifications.TextDocumentDidSave{params: params}, state) do
    uri = params.text_document.uri
    Logger.info("Document saved: #{uri}")

    # Trigger diagnostics on save
    spawn(fn ->
      diagnostics = Diagnostics.handle(%{"textDocument" => %{"uri" => uri}}, state)
      GenLSP.notify(self(), %{
        "method" => "textDocument/publishDiagnostics",
        "params" => diagnostics
      })
    end)

    {:noreply, state}
  end

  @impl true
  def handle_notification(%GenLSP.Notifications.Initialized{}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_notification(%GenLSP.Notifications.Exit{}, state) do
    System.halt(0)
    {:noreply, state}
  end

  @impl true
  def handle_notification(_notification, state) do
    {:noreply, state}
  end

  # Private helpers

  defp handle_deploy(args, state) do
    provider = get_arg(args, "provider", :aws)
    opts = get_arg(args, "opts", [])

    adapter = get_adapter(provider)
    adapter.deploy(state.project_path, opts)
  end

  defp handle_status(args, state) do
    provider = get_arg(args, "provider", :aws)
    opts = get_arg(args, "opts", [])

    adapter = get_adapter(provider)
    adapter.status(state.project_path, opts)
  end

  defp handle_logs(args, state) do
    provider = get_arg(args, "provider", :aws)
    opts = get_arg(args, "opts", [])

    adapter = get_adapter(provider)
    adapter.logs(state.project_path, opts)
  end

  defp handle_configure(args, state) do
    provider = get_arg(args, "provider", :aws)
    opts = get_arg(args, "opts", [])

    adapter = get_adapter(provider)
    adapter.configure(state.project_path, opts)
  end

  defp get_adapter(:aws), do: Adapters.AWS
  defp get_adapter(:gcp), do: Adapters.GCP
  defp get_adapter(:azure), do: Adapters.Azure
  defp get_adapter(:digitalocean), do: Adapters.DigitalOcean
  defp get_adapter(_), do: Adapters.AWS

  defp get_arg(args, key, default) do
    args
    |> Enum.find_value(default, fn arg ->
      if is_map(arg) && Map.has_key?(arg, key), do: Map.get(arg, key)
    end)
  end
end
