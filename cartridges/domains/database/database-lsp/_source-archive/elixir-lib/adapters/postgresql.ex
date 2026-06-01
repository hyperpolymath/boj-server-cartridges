# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyDB.Adapters.PostgreSQL do
  @moduledoc """
  Adapter for PostgreSQL - Advanced open-source relational database.

  ## Configuration

  PostgreSQL can be configured via:
  - `.pgpass` file (connection credentials)
  - `postgresql.conf` (server configuration)
  - Environment variables (PGHOST, PGPORT, PGDATABASE, PGUSER)

  ## CLI Tool

  Uses `psql` for command-line operations.

  ## Default Port

  5432
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
    # Check for PostgreSQL config files or connection info
    pgpass_exists = File.exists?(Path.join(project_path, ".pgpass"))
    env_vars_exist = System.get_env("PGHOST") != nil || System.get_env("PGDATABASE") != nil

    {:ok, pgpass_exists or env_vars_exist}
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
    output_path = Keyword.get(opts, :output_path, "backup.sql")
    format = Keyword.get(opts, :format, :sql)
    compression = Keyword.get(opts, :compression, false)

    args = [
      "-h", connection_info.host,
      "-p", to_string(connection_info.port || 5432),
      "-U", connection_info.user,
      "-d", connection_info.database
    ]

    args = case format do
      :sql -> args ++ ["-f", output_path]
      :binary -> args ++ ["-F", "c", "-f", output_path]
      :custom -> args ++ ["-F", "custom", "-f", output_path]
      _ -> args ++ ["-f", output_path]
    end

    args = if compression, do: args ++ ["-Z", "9"], else: args

    case System.cmd("pg_dump", args, stderr_to_stdout: true) do
      {_output, 0} ->
        {:ok, output_path}

      {error, exit_code} ->
        {:error, "Backup failed (exit #{exit_code}): #{error}"}
    end
  end

  @impl PolyDB.Adapters.Behaviour
  def version do
    case System.cmd("psql", ["--version"], stderr_to_stdout: true) do
      {output, 0} ->
        version = output |> String.trim() |> String.replace(~r/psql \(PostgreSQL\) /, "")
        {:ok, version}

      {error, _} ->
        {:error, error}
    end
  end

  @impl PolyDB.Adapters.Behaviour
  def metadata do
    %{
      name: "PostgreSQL",
      type: :relational,
      description: "Advanced open-source relational database with ACID compliance",
      cli_tool: "psql",
      default_port: 5432,
      config_files: [".pgpass", "postgresql.conf", "pg_hba.conf"]
    }
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %{connections: %{}, queries: %{}}}
  end

  @impl true
  def handle_call({:query, connection_info, query_string}, _from, state) do
    Logger.info("Executing PostgreSQL query")

    # Use psql for query execution
    args = [
      "-h", connection_info.host,
      "-p", to_string(connection_info.port || 5432),
      "-U", connection_info.user,
      "-d", connection_info.database,
      "-c", query_string,
      "-t", # Tuples only
      "-A"  # Unaligned output
    ]

    case System.cmd("psql", args, stderr_to_stdout: true) do
      {output, 0} ->
        rows = output |> String.trim() |> String.split("\n")
        result = %{
          success: true,
          rows: rows,
          row_count: length(rows)
        }

        {:reply, {:ok, result}, state}

      {error, exit_code} ->
        {:reply, {:error, "Query failed (exit #{exit_code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:schema, connection_info}, _from, state) do
    Logger.info("Retrieving PostgreSQL schema")

    # Query to get table information
    schema_query = """
    SELECT
      table_schema,
      table_name,
      column_name,
      data_type,
      is_nullable
    FROM information_schema.columns
    WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
    ORDER BY table_schema, table_name, ordinal_position;
    """

    args = [
      "-h", connection_info.host,
      "-p", to_string(connection_info.port || 5432),
      "-U", connection_info.user,
      "-d", connection_info.database,
      "-c", schema_query,
      "-t",
      "-A"
    ]

    case System.cmd("psql", args, stderr_to_stdout: true) do
      {output, 0} ->
        schema = parse_schema_output(output)
        {:reply, {:ok, schema}, state}

      {error, exit_code} ->
        {:reply, {:error, "Schema retrieval failed (exit #{exit_code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:migrate, connection_info, _opts}, _from, state) do
    Logger.info("Running PostgreSQL migrations")
    # Migration logic would go here
    # For now, return a placeholder
    {:reply, {:ok, %{status: "migrations not implemented yet"}}, state}
  end

  # Private helpers

  defp parse_schema_output(output) do
    tables = output
    |> String.trim()
    |> String.split("\n")
    |> Enum.map(&String.split(&1, "|"))
    |> Enum.group_by(fn [schema, table | _] -> {schema, table} end)

    %{tables: tables, views: [], indexes: []}
  end
end
