# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyDB.Adapters.Neo4j do
  @moduledoc """
  Adapter for Neo4j - Graph database management system.

  ## Configuration

  Neo4j can be configured via:
  - `neo4j.conf` (server configuration)
  - `.neo4jrc` (CLI defaults)

  ## CLI Tool

  Uses `cypher-shell` for command-line operations.

  ## Default Port

  7687 (Bolt protocol), 7474 (HTTP)
  """
  use GenServer
  @behaviour PolyDB.Adapters.Behaviour

  require Logger

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl PolyDB.Adapters.Behaviour
  def detect(project_path) do
    # Check for Neo4j config files
    neo4j_conf_exists = File.exists?(Path.join(project_path, "neo4j.conf"))
    neo4jrc_exists = File.exists?(Path.join(project_path, ".neo4jrc"))

    {:ok, neo4j_conf_exists or neo4jrc_exists}
  end

  @impl PolyDB.Adapters.Behaviour
  def query(connection_info, cypher_query) do
    GenServer.call(__MODULE__, {:query, connection_info, cypher_query})
  end

  @impl PolyDB.Adapters.Behaviour
  def schema(connection_info) do
    GenServer.call(__MODULE__, {:schema, connection_info})
  end

  @impl PolyDB.Adapters.Behaviour
  def migrate(connection_info, opts) do
    GenServer.call(__MODULE__, {:migrate, connection_info, opts})
  end

  @impl PolyDB.Adapters.Behaviour
  def backup(connection_info, opts) do
    output_path = Keyword.get(opts, :output_path, "neo4j-backup")

    # Note: neo4j-admin backup requires enterprise edition
    # For community edition, we can export to cypher-shell format
    args = [
      "-a", "#{connection_info.host}:#{connection_info.port || 7687}",
      "-u", connection_info.user,
      "-p", connection_info[:password] || "",
      "-d", connection_info.database || "neo4j",
      "CALL apoc.export.cypher.all('#{output_path}.cypher', {})"
    ]

    case System.cmd("cypher-shell", args, stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, "#{output_path}.cypher"}

      {error, exit_code} ->
        {:error, "Backup failed (exit #{exit_code}): #{error}"}
    end
  end

  @impl PolyDB.Adapters.Behaviour
  def version do
    case System.cmd("cypher-shell", ["--version"], stderr_to_stdout: true) do
      {output, 0} ->
        version = output |> String.trim()
        {:ok, version}

      {error, _} ->
        {:error, error}
    end
  end

  @impl PolyDB.Adapters.Behaviour
  def metadata do
    %{
      name: "Neo4j",
      type: :graph,
      description: "Graph database management system with native graph storage and processing",
      cli_tool: "cypher-shell",
      default_port: 7687,
      config_files: ["neo4j.conf", ".neo4jrc"]
    }
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %{connections: %{}, queries: %{}}}
  end

  @impl true
  def handle_call({:query, connection_info, cypher_query}, _from, state) do
    Logger.info("Executing Neo4j Cypher query")

    args = [
      "-a", "#{connection_info.host}:#{connection_info.port || 7687}",
      "-u", connection_info.user,
      "-p", connection_info[:password] || "",
      "-d", connection_info.database || "neo4j",
      cypher_query
    ]

    case System.cmd("cypher-shell", args, stderr_to_stdout: true) do
      {output, 0} ->
        result = %{
          success: true,
          output: output |> String.trim()
        }

        {:reply, {:ok, result}, state}

      {error, exit_code} ->
        {:reply, {:error, "Query failed (exit #{exit_code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:schema, connection_info}, _from, state) do
    Logger.info("Retrieving Neo4j schema")

    # Get node labels and relationship types
    schema_query = """
    CALL db.labels() YIELD label
    RETURN collect(label) as labels
    UNION ALL
    CALL db.relationshipTypes() YIELD relationshipType
    RETURN collect(relationshipType) as relationshipTypes
    """

    args = [
      "-a", "#{connection_info.host}:#{connection_info.port || 7687}",
      "-u", connection_info.user,
      "-p", connection_info[:password] || "",
      "-d", connection_info.database || "neo4j",
      "--format", "plain",
      schema_query
    ]

    case System.cmd("cypher-shell", args, stderr_to_stdout: true) do
      {output, 0} ->
        schema = parse_schema_output(output)
        {:reply, {:ok, schema}, state}

      {error, exit_code} ->
        {:reply, {:error, "Schema retrieval failed (exit #{exit_code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:migrate, connection_info, _opts}, _from, state) do
    Logger.info("Running Neo4j migrations")
    # Migration logic would go here
    {:reply, {:ok, %{status: "migrations not implemented yet"}}, state}
  end

  # Private helpers

  defp parse_schema_output(output) do
    # Parse the output to extract labels and relationship types
    lines = output |> String.trim() |> String.split("\n")

    %{
      labels: [],
      relationship_types: [],
      raw_output: lines
    }
  end
end
