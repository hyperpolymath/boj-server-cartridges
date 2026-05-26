# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyOrchestrator.VeriSimDB.Client do
  @moduledoc """
  Client for stapeln's VeriSimDB multi-modal database.

  VeriSimDB stores orchestration history across multiple modalities:
  - Graph: Component dependency relationships
  - Vector: Semantic search for similar stack patterns
  - Document: Full stack.compose.toml files
  - Temporal: Time-series deployment history
  - Semantic: Stack metadata and tags

  ## Integration Architecture

  ```
  poly-orchestrator-lsp
       |
       | GraphQL/HTTP
       ↓
  stapeln Phoenix Backend
       |
       | Native API
       ↓
  VeriSimDB
  ```

  ## Connection Options

  1. **Via stapeln's GraphQL API** (Recommended)
     - Uses stapeln's existing Phoenix + Absinthe backend
     - Respects stapeln's access control and validation
     - Leverages existing connection pooling

  2. **Direct Database Connection** (Future)
     - Native VeriSimDB client (when available)
     - Better performance for bulk operations
     - Requires separate authentication

  ## Usage

      # Store orchestration result
      {:ok, _} = VeriSimDB.Client.store_execution(%{
        stack_id: "my-web-stack",
        timestamp: DateTime.utc_now(),
        components: ["cloud-infrastructure", "postgres-db", ...],
        status: :success,
        duration_ms: 45_000
      })

      # Query past deployments
      {:ok, history} = VeriSimDB.Client.query_history(%{
        stack_id: "my-web-stack",
        time_range: {~U[2026-01-01 00:00:00Z], DateTime.utc_now()}
      })

      # Semantic search for similar stacks
      {:ok, similar} = VeriSimDB.Client.find_similar_stacks(
        "e-commerce stack with PostgreSQL and Redis"
      )
  """

  use Tesla

  plug Tesla.Middleware.BaseUrl, Application.get_env(:poly_orchestrator_lsp, :stapeln_url)
  plug Tesla.Middleware.Headers, [{"content-type", "application/json"}]
  plug Tesla.Middleware.JSON

  @doc """
  Store orchestration execution result in VeriSimDB via stapeln's GraphQL API.
  """
  def store_execution(execution_data) do
    mutation = """
    mutation StoreOrchestrationExecution($input: ExecutionInput!) {
      storeExecution(input: $input) {
        id
        stackId
        timestamp
        status
      }
    }
    """

    variables = %{input: execution_data}

    post("/graphql", %{query: mutation, variables: variables})
    |> handle_response()
  end

  @doc """
  Query orchestration history from VeriSimDB.

  Uses temporal query capabilities to retrieve time-range data.
  """
  def query_history(query_params) do
    query = """
    query OrchestrationHistory($stackId: String!, $timeRange: TimeRange!) {
      orchestrationHistory(stackId: $stackId, timeRange: $timeRange) {
        executions {
          id
          timestamp
          status
          durationMs
          components {
            id
            type
            status
          }
        }
      }
    }
    """

    variables = %{
      stackId: query_params.stack_id,
      timeRange: serialize_time_range(query_params.time_range)
    }

    post("/graphql", %{query: query, variables: variables})
    |> handle_response()
  end

  @doc """
  Semantic search for similar stack patterns.

  Uses VeriSimDB's vector store to find stacks with similar characteristics.
  """
  def find_similar_stacks(description, limit \\ 10) do
    query = """
    query SimilarStacks($description: String!, $limit: Int!) {
      findSimilarStacks(description: $description, limit: $limit) {
        id
        name
        description
        similarity
        components {
          type
          count
        }
      }
    }
    """

    variables = %{description: description, limit: limit}

    post("/graphql", %{query: query, variables: variables})
    |> handle_response()
  end

  @doc """
  Store the dependency graph for a stack.

  Uses VeriSimDB's graph database capabilities.
  """
  def store_dependency_graph(stack_id, graph) do
    mutation = """
    mutation StoreDependencyGraph($stackId: String!, $graph: GraphInput!) {
      storeDependencyGraph(stackId: $stackId, graph: $graph) {
        success
        nodeCount
        edgeCount
      }
    }
    """

    variables = %{
      stackId: stack_id,
      graph: serialize_graph(graph)
    }

    post("/graphql", %{query: mutation, variables: variables})
    |> handle_response()
  end

  @doc """
  Query the dependency graph for rollback planning.

  Returns nodes that depend on a given component.
  """
  def query_dependents(component_id) do
    query = """
    query ComponentDependents($componentId: String!) {
      componentDependents(componentId: $componentId) {
        id
        type
        depth
        path
      }
    }
    """

    variables = %{componentId: component_id}

    post("/graphql", %{query: query, variables: variables})
    |> handle_response()
  end

  # Private helpers

  defp handle_response({:ok, %{status: 200, body: %{"data" => data}}}) do
    {:ok, data}
  end

  defp handle_response({:ok, %{status: 200, body: %{"errors" => errors}}}) do
    {:error, {:graphql_errors, errors}}
  end

  defp handle_response({:ok, %{status: status}}) do
    {:error, {:http_error, status}}
  end

  defp handle_response({:error, reason}) do
    {:error, {:connection_error, reason}}
  end

  defp serialize_time_range({start_time, end_time}) do
    %{
      start: DateTime.to_iso8601(start_time),
      end: DateTime.to_iso8601(end_time)
    }
  end

  defp serialize_graph(graph) do
    %{
      nodes: Enum.map(graph.vertices, &serialize_node/1),
      edges: Enum.map(graph.edges, &serialize_edge/1)
    }
  end

  defp serialize_node(vertex) do
    %{
      id: vertex.id,
      type: vertex.type,
      properties: vertex.properties || %{}
    }
  end

  defp serialize_edge({from, to, label}) do
    %{from: from, to: to, label: label}
  end
end
