# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyDB.Adapters.SQLite do
  @moduledoc """
  Adapter for SQLite - Lightweight embedded SQL database.

  ## Configuration

  SQLite uses individual database files (*.db, *.sqlite, *.sqlite3).
  No server configuration needed.

  ## CLI Tool

  Uses `sqlite3` for command-line operations.

  ## Default Port

  N/A (file-based, no network port)
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
    # Check for SQLite database files
    db_files = Path.wildcard(Path.join(project_path, "*.{db,sqlite,sqlite3}"))
    {:ok, length(db_files) > 0}
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
    output_path = Keyword.get(opts, :output_path, "backup.db")
    db_path = connection_info.database

    # Use sqlite3 .backup command
    backup_command = ".backup '#{output_path}'"

    case System.cmd("sqlite3", [db_path, backup_command], stderr_to_stdout: true) do
      {_output, 0} ->
        {:ok, output_path}

      {error, exit_code} ->
        {:error, "Backup failed (exit #{exit_code}): #{error}"}
    end
  end

  @impl PolyDB.Adapters.Behaviour
  def version do
    case System.cmd("sqlite3", ["--version"], stderr_to_stdout: true) do
      {output, 0} ->
        version = output |> String.trim() |> String.split(" ") |> List.first()
        {:ok, version}

      {error, _} ->
        {:error, error}
    end
  end

  @impl PolyDB.Adapters.Behaviour
  def metadata do
    %{
      name: "SQLite",
      type: :relational,
      description: "Lightweight embedded SQL database engine",
      cli_tool: "sqlite3",
      default_port: 0,  # File-based, no network port
      config_files: []  # No config files, uses database files directly
    }
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %{connections: %{}, queries: %{}}}
  end

  @impl true
  def handle_call({:query, connection_info, query_string}, _from, state) do
    Logger.info("Executing SQLite query")

    db_path = connection_info.database

    args = [
      db_path,
      "-batch",
      "-noheader",
      query_string
    ]

    case System.cmd("sqlite3", args, stderr_to_stdout: true) do
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
    Logger.info("Retrieving SQLite schema")

    db_path = connection_info.database

    # Get table schema
    schema_command = ".schema"

    args = [db_path, schema_command]

    case System.cmd("sqlite3", args, stderr_to_stdout: true) do
      {output, 0} ->
        schema = parse_schema_output(output)
        {:reply, {:ok, schema}, state}

      {error, exit_code} ->
        {:reply, {:error, "Schema retrieval failed (exit #{exit_code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:migrate, connection_info, _opts}, _from, state) do
    Logger.info("Running SQLite migrations")
    # Migration logic would go here
    {:reply, {:ok, %{status: "migrations not implemented yet"}}, state}
  end

  # Private helpers

  defp parse_schema_output(output) do
    # Extract CREATE TABLE statements
    tables = output
    |> String.split("CREATE TABLE")
    |> Enum.drop(1)  # Skip first empty element
    |> Enum.map(fn table_def ->
      table_name = table_def
      |> String.split("(")
      |> List.first()
      |> String.trim()

      {table_name, table_def}
    end)
    |> Enum.into(%{})

    %{
      tables: tables,
      views: [],
      indexes: [],
      raw_schema: output
    }
  end
end
