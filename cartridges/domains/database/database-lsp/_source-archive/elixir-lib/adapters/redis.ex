# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyDB.Adapters.Redis do
  @moduledoc """
  Adapter for Redis - In-memory data structure store.

  ## Configuration

  Redis can be configured via:
  - `redis.conf` (server configuration)
  - `.redisrc` (CLI defaults)

  ## CLI Tool

  Uses `redis-cli` for command-line operations.

  ## Default Port

  6379
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
    # Check for Redis config files
    redis_conf_exists = File.exists?(Path.join(project_path, "redis.conf"))
    redisrc_exists = File.exists?(Path.join(project_path, ".redisrc"))

    {:ok, redis_conf_exists or redisrc_exists}
  end

  @impl PolyDB.Adapters.Behaviour
  def query(connection_info, command) do
    GenServer.call(__MODULE__, {:query, connection_info, command})
  end

  @impl PolyDB.Adapters.Behaviour
  def schema(connection_info) do
    GenServer.call(__MODULE__, {:schema, connection_info})
  end

  @impl PolyDB.Adapters.Behaviour
  def migrate(_connection_info, _opts) do
    # Redis doesn't have traditional migrations
    {:ok, %{status: "Redis does not support migrations"}}
  end

  @impl PolyDB.Adapters.Behaviour
  def backup(connection_info, opts) do
    output_path = Keyword.get(opts, :output_path, "dump.rdb")

    # Trigger a BGSAVE and copy the dump file
    args = [
      "-h", connection_info.host,
      "-p", to_string(connection_info.port || 6379),
      "BGSAVE"
    ]

    case System.cmd("redis-cli", args, stderr_to_stdout: true) do
      {output, 0} ->
        if String.contains?(output, "Background saving started") do
          {:ok, output_path}
        else
          {:error, "BGSAVE did not start: #{output}"}
        end

      {error, exit_code} ->
        {:error, "Backup failed (exit #{exit_code}): #{error}"}
    end
  end

  @impl PolyDB.Adapters.Behaviour
  def version do
    case System.cmd("redis-cli", ["--version"], stderr_to_stdout: true) do
      {output, 0} ->
        version = output |> String.trim() |> String.replace("redis-cli ", "")
        {:ok, version}

      {error, _} ->
        {:error, error}
    end
  end

  @impl PolyDB.Adapters.Behaviour
  def metadata do
    %{
      name: "Redis",
      type: :key_value,
      description: "In-memory data structure store used as database, cache, and message broker",
      cli_tool: "redis-cli",
      default_port: 6379,
      config_files: ["redis.conf", ".redisrc"]
    }
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %{connections: %{}, commands: %{}}}
  end

  @impl true
  def handle_call({:query, connection_info, command}, _from, state) do
    Logger.info("Executing Redis command: #{command}")

    args = [
      "-h", connection_info.host,
      "-p", to_string(connection_info.port || 6379)
    ] ++ String.split(command, " ")

    case System.cmd("redis-cli", args, stderr_to_stdout: true) do
      {output, 0} ->
        result = %{
          success: true,
          output: output |> String.trim()
        }

        {:reply, {:ok, result}, state}

      {error, exit_code} ->
        {:reply, {:error, "Command failed (exit #{exit_code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:schema, connection_info}, _from, state) do
    Logger.info("Retrieving Redis schema (key patterns)")

    # Get database info and key statistics
    args = [
      "-h", connection_info.host,
      "-p", to_string(connection_info.port || 6379),
      "INFO", "keyspace"
    ]

    case System.cmd("redis-cli", args, stderr_to_stdout: true) do
      {output, 0} ->
        schema = parse_keyspace_info(output)
        {:reply, {:ok, schema}, state}

      {error, exit_code} ->
        {:reply, {:error, "Schema retrieval failed (exit #{exit_code}): #{error}"}, state}
    end
  end

  # Private helpers

  defp parse_keyspace_info(output) do
    lines = output |> String.trim() |> String.split("\n")

    keyspace_data = lines
    |> Enum.filter(&String.starts_with?(&1, "db"))
    |> Enum.map(fn line ->
      [db | rest] = String.split(line, ":")
      {db, Enum.join(rest, ":")}
    end)
    |> Enum.into(%{})

    %{
      keyspace: keyspace_data,
      databases: Map.keys(keyspace_data)
    }
  end
end
