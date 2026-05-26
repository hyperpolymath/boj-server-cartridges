# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyDB.Adapters.MySQL do
  @moduledoc """
  Adapter for MySQL - Open-source relational database.

  ## Configuration

  MySQL can be configured via:
  - `my.cnf` or `.my.cnf` (configuration file)
  - `.mylogin.cnf` (encrypted login credentials)

  ## CLI Tool

  Uses `mysql` for command-line operations.

  ## Default Port

  3306
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
    # Check for MySQL config files
    my_cnf_exists = File.exists?(Path.join(project_path, "my.cnf")) ||
                    File.exists?(Path.join(project_path, ".my.cnf"))

    {:ok, my_cnf_exists}
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

    args = [
      "-h", connection_info.host,
      "-P", to_string(connection_info.port || 3306),
      "-u", connection_info.user,
      connection_info.database,
      "--result-file=#{output_path}"
    ]

    # Add password if provided
    args = if connection_info[:password] do
      args ++ ["-p#{connection_info.password}"]
    else
      args
    end

    case System.cmd("mysqldump", args, stderr_to_stdout: true) do
      {_output, 0} ->
        {:ok, output_path}

      {error, exit_code} ->
        {:error, "Backup failed (exit #{exit_code}): #{error}"}
    end
  end

  @impl PolyDB.Adapters.Behaviour
  def version do
    case System.cmd("mysql", ["--version"], stderr_to_stdout: true) do
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
      name: "MySQL",
      type: :relational,
      description: "Open-source relational database management system",
      cli_tool: "mysql",
      default_port: 3306,
      config_files: ["my.cnf", ".my.cnf", ".mylogin.cnf"]
    }
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %{connections: %{}, queries: %{}}}
  end

  @impl true
  def handle_call({:query, connection_info, query_string}, _from, state) do
    Logger.info("Executing MySQL query")

    args = [
      "-h", connection_info.host,
      "-P", to_string(connection_info.port || 3306),
      "-u", connection_info.user,
      "-D", connection_info.database,
      "-e", query_string,
      "--batch",  # Tab-separated output
      "--skip-column-names"
    ]

    # Add password if provided
    args = if connection_info[:password] do
      ["-p#{connection_info.password}"] ++ args
    else
      args
    end

    case System.cmd("mysql", args, stderr_to_stdout: true) do
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
    Logger.info("Retrieving MySQL schema")

    # Query to get table information
    schema_query = """
    SELECT
      TABLE_SCHEMA,
      TABLE_NAME,
      COLUMN_NAME,
      DATA_TYPE,
      IS_NULLABLE
    FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = '#{connection_info.database}'
    ORDER BY TABLE_NAME, ORDINAL_POSITION;
    """

    args = [
      "-h", connection_info.host,
      "-P", to_string(connection_info.port || 3306),
      "-u", connection_info.user,
      "-e", schema_query,
      "--batch",
      "--skip-column-names"
    ]

    # Add password if provided
    args = if connection_info[:password] do
      ["-p#{connection_info.password}"] ++ args
    else
      args
    end

    case System.cmd("mysql", args, stderr_to_stdout: true) do
      {output, 0} ->
        schema = parse_schema_output(output)
        {:reply, {:ok, schema}, state}

      {error, exit_code} ->
        {:reply, {:error, "Schema retrieval failed (exit #{exit_code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:migrate, connection_info, _opts}, _from, state) do
    Logger.info("Running MySQL migrations")
    # Migration logic would go here
    {:reply, {:ok, %{status: "migrations not implemented yet"}}, state}
  end

  # Private helpers

  defp parse_schema_output(output) do
    tables = output
    |> String.trim()
    |> String.split("\n")
    |> Enum.map(&String.split(&1, "\t"))
    |> Enum.group_by(fn [_schema, table | _] -> table end)

    %{tables: tables, views: [], indexes: []}
  end
end
