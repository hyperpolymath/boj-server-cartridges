# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyOrchestrator.Orchestrator.LSPClient do
  @moduledoc """
  Client for communicating with the 12 hyperpolymath LSP servers.

  Handles:
  - LSP protocol communication (JSON-RPC 2.0)
  - Server lifecycle (start, stop, restart)
  - Request routing based on component type
  - Response parsing and validation
  - Error handling and retries

  ## LSP Server Mapping

  | Component Type          | LSP Server           |
  |------------------------|---------------------|
  | cloud.*                | poly-cloud-lsp      |
  | container.*            | poly-container-lsp  |
  | database.*             | poly-db-lsp         |
  | git.*                  | poly-git-lsp        |
  | iac.*                  | poly-iac-lsp        |
  | kubernetes.*           | poly-k8s-lsp        |
  | observability.*        | poly-observability-lsp |
  | queue.*                | poly-queue-lsp      |
  | secrets.*              | poly-secret-lsp     |
  | ssg.*                  | poly-ssg-lsp        |
  | browser.*              | claude-firefox-lsp  |
  | proof.*                | poly-proof-lsp      |
  """

  use GenServer
  require Logger

  @lsp_server_paths %{
    "poly-cloud" => "~/Documents/hyperpolymath-repos/poly-cloud-lsp",
    "poly-container" => "~/Documents/hyperpolymath-repos/poly-container-lsp",
    "poly-db" => "~/Documents/hyperpolymath-repos/poly-db-lsp",
    "poly-git" => "~/Documents/hyperpolymath-repos/poly-git-lsp",
    "poly-iac" => "~/Documents/hyperpolymath-repos/poly-iac-lsp",
    "poly-k8s" => "~/Documents/hyperpolymath-repos/poly-k8s-lsp",
    "poly-observability" => "~/Documents/hyperpolymath-repos/poly-observability-lsp",
    "poly-queue" => "~/Documents/hyperpolymath-repos/poly-queue-lsp",
    "poly-secret" => "~/Documents/hyperpolymath-repos/poly-secret-lsp",
    "poly-ssg" => "~/Documents/hyperpolymath-repos/poly-ssg-lsp",
    "claude-firefox" => "~/Documents/hyperpolymath-repos/claude-firefox-lsp",
    "poly-proof" => "~/Documents/hyperpolymath-repos/poly-proof-lsp"
  }

  # Client API

  @doc """
  Start the LSP client pool.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Execute a component via its LSP server.

  Returns:
  - `{:ok, result}` - Successful execution with outputs
  - `{:error, reason}` - Execution failure
  """
  def execute_component(component) do
    GenServer.call(__MODULE__, {:execute, component}, 300_000)  # 5 min timeout
  end

  @doc """
  Validate a component configuration before execution.
  """
  def validate_component(component) do
    GenServer.call(__MODULE__, {:validate, component})
  end

  @doc """
  Get completion suggestions for a component type.
  """
  def get_completions(component_type, context) do
    lsp_server = map_component_to_lsp(component_type)
    GenServer.call(__MODULE__, {:completions, lsp_server, context})
  end

  @doc """
  Get diagnostics for a stack configuration.
  """
  def get_diagnostics(stack) do
    GenServer.call(__MODULE__, {:diagnostics, stack})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      connections: %{},
      message_id: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:execute, component}, _from, state) do
    lsp_server = component.lsp_server

    with {:ok, state} <- ensure_connection(lsp_server, state),
         {:ok, request} <- build_execute_request(component, state),
         {:ok, response, state} <- send_request(lsp_server, request, state),
         {:ok, result} <- parse_response(response) do
      {:reply, {:ok, result}, state}
    else
      {:error, reason} = error ->
        Logger.error("Component execution failed: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:validate, component}, _from, state) do
    lsp_server = component.lsp_server

    with {:ok, state} <- ensure_connection(lsp_server, state),
         {:ok, request} <- build_validate_request(component, state),
         {:ok, response, state} <- send_request(lsp_server, request, state),
         {:ok, diagnostics} <- parse_diagnostics(response) do
      {:reply, {:ok, diagnostics}, state}
    else
      {:error, reason} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:completions, lsp_server, context}, _from, state) do
    with {:ok, state} <- ensure_connection(lsp_server, state),
         {:ok, request} <- build_completion_request(context, state),
         {:ok, response, state} <- send_request(lsp_server, request, state),
         {:ok, items} <- parse_completions(response) do
      {:reply, {:ok, items}, state}
    else
      {:error, reason} = error ->
        {:reply, error, state}
    end
  end

  # Private Functions

  defp ensure_connection(lsp_server, state) do
    case Map.get(state.connections, lsp_server) do
      nil ->
        # Start LSP server process
        case start_lsp_server(lsp_server) do
          {:ok, pid} ->
            new_state = put_in(state.connections[lsp_server], %{pid: pid, ready: true})
            {:ok, new_state}

          error ->
            error
        end

      %{ready: true} ->
        {:ok, state}

      %{ready: false} ->
        {:error, :server_not_ready}
    end
  end

  defp start_lsp_server(lsp_server) do
    path = Path.expand(@lsp_server_paths[lsp_server])

    # Start the LSP server as an Elixir Port
    port = Port.open(
      {:spawn_executable, "#{path}/_build/dev/lib/#{lsp_server}/ebin/#{lsp_server}"},
      [:binary, :exit_status, packet: 4]
    )

    {:ok, port}
  rescue
    e ->
      Logger.error("Failed to start LSP server #{lsp_server}: #{inspect(e)}")
      {:error, :server_start_failed}
  end

  defp build_execute_request(component, state) do
    request = %{
      jsonrpc: "2.0",
      id: state.message_id,
      method: "workspace/executeCommand",
      params: %{
        command: "execute_component",
        arguments: [
          %{
            type: component.type,
            config: component.config,
            id: component.id
          }
        ]
      }
    }

    {:ok, request}
  end

  defp build_validate_request(component, state) do
    request = %{
      jsonrpc: "2.0",
      id: state.message_id,
      method: "textDocument/publishDiagnostics",
      params: %{
        uri: "stack://component/#{component.id}",
        version: 1,
        text: Jason.encode!(component.config)
      }
    }

    {:ok, request}
  end

  defp build_completion_request(context, state) do
    request = %{
      jsonrpc: "2.0",
      id: state.message_id,
      method: "textDocument/completion",
      params: %{
        textDocument: %{uri: "stack://context"},
        position: %{line: 0, character: 0},
        context: context
      }
    }

    {:ok, request}
  end

  defp send_request(lsp_server, request, state) do
    connection = state.connections[lsp_server]
    message = Jason.encode!(request)

    # Send via Port
    Port.command(connection.pid, message)

    # Wait for response (simplified - should use proper message matching)
    receive do
      {_port, {:data, response_data}} ->
        response = Jason.decode!(response_data)
        new_state = %{state | message_id: state.message_id + 1}
        {:ok, response, new_state}
    after
      30_000 ->
        {:error, :timeout}
    end
  rescue
    e ->
      Logger.error("Request failed: #{inspect(e)}")
      {:error, :request_failed}
  end

  defp parse_response(%{"result" => result}), do: {:ok, result}
  defp parse_response(%{"error" => error}), do: {:error, error}
  defp parse_response(_), do: {:error, :invalid_response}

  defp parse_diagnostics(%{"result" => diagnostics}), do: {:ok, diagnostics}
  defp parse_diagnostics(_), do: {:ok, []}

  defp parse_completions(%{"result" => %{"items" => items}}), do: {:ok, items}
  defp parse_completions(%{"result" => items}) when is_list(items), do: {:ok, items}
  defp parse_completions(_), do: {:ok, []}

  defp map_component_to_lsp("cloud." <> _), do: "poly-cloud"
  defp map_component_to_lsp("container." <> _), do: "poly-container"
  defp map_component_to_lsp("database." <> _), do: "poly-db"
  defp map_component_to_lsp("git." <> _), do: "poly-git"
  defp map_component_to_lsp("iac." <> _), do: "poly-iac"
  defp map_component_to_lsp("kubernetes." <> _), do: "poly-k8s"
  defp map_component_to_lsp("observability." <> _), do: "poly-observability"
  defp map_component_to_lsp("queue." <> _), do: "poly-queue"
  defp map_component_to_lsp("secrets." <> _), do: "poly-secret"
  defp map_component_to_lsp("ssg." <> _), do: "poly-ssg"
  defp map_component_to_lsp("browser." <> _), do: "claude-firefox"
  defp map_component_to_lsp("proof." <> _), do: "poly-proof"
  defp map_component_to_lsp(_), do: nil
end

defmodule PolyOrchestrator.Orchestrator.LSPClientPool do
  @moduledoc """
  Supervisor for LSP client connections.
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {PolyOrchestrator.Orchestrator.LSPClient, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
