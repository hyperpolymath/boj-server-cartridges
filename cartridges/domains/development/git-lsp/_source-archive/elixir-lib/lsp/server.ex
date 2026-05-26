# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyGit.LSP.Server do
  @moduledoc """
  LSP server implementation for Git forge management.

  Provides LSP features for Git configuration and commit message files.
  """
  use GenLSP

  require Logger

  alias PolyGit.LSP.Handlers.{Completion, Diagnostics, Hover}

  def start_link(args) do
    GenLSP.start_link(__MODULE__, args, [])
  end

  @impl GenLSP
  def init(_lsp, args) do
    {:ok, %{
      project_path: args[:project_path] || File.cwd!(),
      documents: %{}
    }}
  end

  @impl GenLSP
  def handle_request(%{"method" => "initialize", "params" => params}, lsp) do
    project_path = get_in(params, ["rootUri"]) |> parse_uri()

    Logger.info("Initializing PolyGit LSP for project: #{inspect(project_path)}")

    server_capabilities = %{
      "textDocumentSync" => %{
        "openClose" => true,
        "change" => 1,
        "save" => %{"includeText" => false}
      },
      "completionProvider" => %{
        "triggerCharacters" => [":", " ", "#"],
        "resolveProvider" => false
      },
      "hoverProvider" => true,
      "executeCommandProvider" => %{
        "commands" => [
          "poly-git.createRepo",
          "poly-git.createPR",
          "poly-git.createIssue",
          "poly-git.listPRs",
          "poly-git.mergePR",
          "poly-git.detectForge"
        ]
      }
    }

    result = %{
      "capabilities" => server_capabilities,
      "serverInfo" => %{
        "name" => "PolyGit LSP",
        "version" => "0.1.0"
      }
    }

    new_state = Map.merge(lsp, %{project_path: project_path})
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

    result = case command do
      "poly-git.detectForge" ->
        project_path = List.first(args) || lsp.assigns.project_path
        forges = PolyGit.LSP.detect_forge(project_path)
        forge_names = Enum.map(forges, &adapter_name/1)
        %{forges: forge_names}

      _ ->
        %{error: "Unknown command"}
    end

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

    documents = Map.put(lsp.assigns.documents, uri, %{text: text, version: version})
    new_state = put_in(lsp.assigns.documents, documents)

    spawn(fn ->
      diagnostics = Diagnostics.handle(params, new_state.assigns)
      GenLSP.notify(lsp, %{"method" => "textDocument/publishDiagnostics", "params" => diagnostics})
    end)

    {:noreply, new_state}
  end

  @impl GenLSP
  def handle_notification(%{"method" => "textDocument/didChange", "params" => params}, lsp) do
    uri = params["textDocument"]["uri"]
    changes = params["contentChanges"]
    version = params["textDocument"]["version"]

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

    documents = Map.delete(lsp.assigns.documents, uri)
    new_state = put_in(lsp.assigns.documents, documents)

    {:noreply, new_state}
  end

  @impl GenLSP
  def handle_notification(%{"method" => "textDocument/didSave", "params" => params}, lsp) do
    uri = params["textDocument"]["uri"]
    Logger.info("File saved: #{uri}")

    spawn(fn ->
      diagnostics = Diagnostics.handle(params, lsp.assigns)
      GenLSP.notify(lsp, %{"method" => "textDocument/publishDiagnostics", "params" => diagnostics})
    end)

    {:noreply, lsp}
  end

  @impl GenLSP
  def handle_notification(_notification, lsp), do: {:noreply, lsp}

  @impl GenLSP
  def handle_info(_msg, lsp), do: {:noreply, lsp}

  # Private helpers

  defp parse_uri(nil), do: nil
  defp parse_uri(uri) when is_binary(uri) do
    case URI.parse(uri) do
      %URI{scheme: "file", path: path} -> path
      _ -> nil
    end
  end

  defp adapter_name(PolyGit.Adapters.GitHub), do: "GitHub"
  defp adapter_name(PolyGit.Adapters.GitLab), do: "GitLab"
  defp adapter_name(PolyGit.Adapters.Gitea), do: "Gitea"
  defp adapter_name(PolyGit.Adapters.Bitbucket), do: "Bitbucket"
  defp adapter_name(_), do: "Unknown"
end
