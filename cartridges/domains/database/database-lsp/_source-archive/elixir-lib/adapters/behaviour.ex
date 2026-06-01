# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyDB.Adapters.Behaviour do
  @moduledoc """
  Behaviour defining the contract for database adapters.

  Each adapter implements this behaviour to provide a consistent interface
  for detecting, querying, and managing database systems.

  ## Example

      defmodule PolyDB.Adapters.PostgreSQL do
        use GenServer
        @behaviour PolyDB.Adapters.Behaviour

        @impl true
        def detect(project_path) do
          config_exists = has_psql_config?(project_path)
          {:ok, config_exists}
        end

        @impl true
        def query(connection_info, sql) do
          # Execute query against PostgreSQL
        end
      end
  """

  @type project_path :: String.t()
  @type connection_info :: map()
  @type query_result :: {:ok, map()} | {:error, String.t()}
  @type detect_result :: {:ok, boolean()} | {:error, String.t()}
  @type schema_result :: {:ok, map()} | {:error, String.t()}
  @type backup_result :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Detect if this database system is present or configured in the project directory.

  Returns `{:ok, true}` if database config files exist, `{:ok, false}` otherwise.
  """
  @callback detect(project_path) :: detect_result

  @doc """
  Execute a query against the database.

  ## Parameters

  - `connection_info` - Connection parameters (host, port, user, password, database)
  - `query` - SQL or database-specific query string

  ## Returns

  - `{:ok, %{rows: [...], columns: [...], row_count: n}}` on success
  - `{:error, reason}` on failure
  """
  @callback query(connection_info, query :: String.t()) :: query_result

  @doc """
  Retrieve schema information from the database.

  Returns metadata about tables, columns, indexes, constraints, etc.

  ## Returns

  - `{:ok, %{tables: [...], views: [...], indexes: [...]}}`
  """
  @callback schema(connection_info) :: schema_result

  @doc """
  Run database migrations.

  ## Options

  - `:direction` - `:up` or `:down`
  - `:version` - Specific version to migrate to (optional)
  """
  @callback migrate(connection_info, opts :: keyword()) ::
              {:ok, map()} | {:error, String.t()}

  @doc """
  Create a database backup.

  ## Options

  - `:output_path` - Where to save the backup
  - `:format` - Backup format (`:sql`, `:binary`, `:custom`)
  - `:compression` - Enable compression (boolean)

  ## Returns

  - `{:ok, backup_path}` with path to backup file
  """
  @callback backup(connection_info, opts :: keyword()) :: backup_result

  @doc """
  Get database system version.
  """
  @callback version() :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Get database system metadata (name, type, CLI tool, default port).
  """
  @callback metadata() :: %{
              name: String.t(),
              type: atom(),
              description: String.t(),
              cli_tool: String.t(),
              default_port: pos_integer(),
              config_files: [String.t()]
            }
end
