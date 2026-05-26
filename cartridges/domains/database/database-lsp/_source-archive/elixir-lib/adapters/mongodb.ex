# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyDB.Adapters.MongoDB do
  @moduledoc """
  Adapter for MongoDB - Document-oriented NoSQL database.

  ## Configuration

  MongoDB can be configured via:
  - `.mongorc.js` (MongoDB shell initialization)
  - `mongod.conf` (server configuration)
  - Connection strings (mongodb://...)

  ## CLI Tool

  Uses `mongosh` (MongoDB Shell) for command-line operations.

  ## Default Port

  27017
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
    # Check for MongoDB config files
    mongorc_exists = File.exists?(Path.join(project_path, ".mongorc.js"))
    mongod_conf_exists = File.exists?(Path.join(project_path, "mongod.conf"))

    {:ok, mongorc_exists or mongod_conf_exists}
  end

  @impl PolyDB.Adapters.Behaviour
  def query(connection_info, query_string) do
    GenServer.call(__MODULE__, {:query, connection_info, query_string})
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
    output_path = Keyword.get(opts, :output_path, "backup")

    args = [
      "--host", connection_info.host,
      "--port", to_string(connection_info.port || 27017),
      "--db", connection_info.database,
      "--out", output_path
    ]

    args = if connection_info[:user] do
      args ++ ["--username", connection_info.user]
    else
      args
    end

    case System.cmd("mongodump", args, stderr_to_stdout: true) do
      {_output, 0} ->
        {:ok, output_path}

      {error, exit_code} ->
        {:error, "Backup failed (exit #{exit_code}): #{error}"}
    end
  end

  @impl PolyDB.Adapters.Behaviour
  def version do
    case System.cmd("mongosh", ["--version"], stderr_to_stdout: true) do
      {output, 0} ->
        version = output |> String.trim() |> String.split("\n") |> List.first()
        {:ok, version}

      {error, _} ->
        {:error, error}
    end
  end

  @impl PolyDB.Adapters.Behaviour
  def metadata do
    %{
      name: "MongoDB",
      type: :document,
      description: "Document-oriented NoSQL database with flexible schema",
      cli_tool: "mongosh",
      default_port: 27017,
      config_files: [".mongorc.js", "mongod.conf"]
    }
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %{connections: %{}, queries: %{}}}
  end

  @impl true
  def handle_call({:query, connection_info, query_string}, _from, state) do
    Logger.info("Executing MongoDB query")

    # Build connection string
    conn_str = build_connection_string(connection_info)

    # Execute query using mongosh
    args = [
      conn_str,
      "--quiet",
      "--eval", query_string
    ]

    case System.cmd("mongosh", args, stderr_to_stdout: true) do
      {output, 0} ->
        result = %{
          success: true,
          output: output |> String.trim(),
          row_count: nil
        }

        {:reply, {:ok, result}, state}

      {error, exit_code} ->
        {:reply, {:error, "Query failed (exit #{exit_code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:schema, connection_info}, _from, state) do
    Logger.info("Retrieving MongoDB schema")

    # Get list of collections
    conn_str = build_connection_string(connection_info)
    query = "db.getCollectionNames()"

    args = [
      conn_str,
      "--quiet",
      "--eval", query
    ]

    case System.cmd("mongosh", args, stderr_to_stdout: true) do
      {output, 0} ->
        collections = output |> String.trim() |> parse_collections()
        schema = %{collections: collections, indexes: []}
        {:reply, {:ok, schema}, state}

      {error, exit_code} ->
        {:reply, {:error, "Schema retrieval failed (exit #{exit_code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:migrate, connection_info, _opts}, _from, state) do
    Logger.info("Running MongoDB migrations")
    # Migration logic would go here
    {:reply, {:ok, %{status: "migrations not implemented yet"}}, state}
  end

  # Private helpers

  defp build_connection_string(connection_info) do
    host = connection_info.host
    port = connection_info.port || 27017
    database = connection_info.database

    if connection_info[:user] do
      user = connection_info.user
      password = connection_info[:password] || ""
      "mongodb://#{user}:#{password}@#{host}:#{port}/#{database}"
    else
      "mongodb://#{host}:#{port}/#{database}"
    end
  end

  defp parse_collections(output) do
    # Parse JSON array of collection names
    case Jason.decode(output) do
      {:ok, collections} when is_list(collections) -> collections
      _ -> []
    end
  end
end
