# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyQueue.Adapters.RedisStreams do
  @moduledoc """
  Redis Streams adapter for PolyQueue LSP.

  Uses redis-cli for command execution and provides access to Redis Streams
  functionality including XADD, XREAD, XGROUP, and stream management.
  """

  use GenServer
  @behaviour PolyQueue.Adapters.Behaviour

  require Logger

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl PolyQueue.Adapters.Behaviour
  def detect do
    case System.cmd("redis-cli", ["--version"], stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.contains?(output, "redis-cli")}
      _ -> {:ok, false}
    end
  rescue
    _ -> {:ok, false}
  end

  @impl PolyQueue.Adapters.Behaviour
  def publish(queue_name, message, opts \\ []) do
    message_map = prepare_message(message)
    fields = Enum.flat_map(message_map, fn {k, v} -> [to_string(k), to_string(v)] end)

    args = ["XADD", queue_name, "*"] ++ fields

    case redis_command(args) do
      {:ok, message_id} -> {:ok, String.trim(message_id)}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl PolyQueue.Adapters.Behaviour
  def subscribe(queue_name, opts \\ []) do
    consumer_group = Keyword.get(opts, :consumer_group, "default-group")
    consumer_name = Keyword.get(opts, :consumer_name, "consumer-1")
    count = Keyword.get(opts, :count, 10)
    block = Keyword.get(opts, :block, 0)
    start_id = Keyword.get(opts, :start_id, ">")

    # Ensure consumer group exists
    create_consumer_group(queue_name, consumer_group)

    args = [
      "XREADGROUP",
      "GROUP",
      consumer_group,
      consumer_name,
      "COUNT",
      to_string(count),
      "BLOCK",
      to_string(block),
      "STREAMS",
      queue_name,
      start_id
    ]

    case redis_command(args) do
      {:ok, result} -> parse_xread_result(result)
      {:error, reason} -> {:error, reason}
    end
  end

  @impl PolyQueue.Adapters.Behaviour
  def list_queues do
    # Use SCAN to find stream keys
    case redis_command(["SCAN", "0", "TYPE", "stream"]) do
      {:ok, result} -> parse_scan_result(result)
      {:error, reason} -> {:error, reason}
    end
  end

  @impl PolyQueue.Adapters.Behaviour
  def queue_status(queue_name) do
    with {:ok, length} <- get_stream_length(queue_name),
         {:ok, groups} <- get_consumer_groups(queue_name),
         {:ok, last_id} <- get_last_id(queue_name) do
      {:ok,
       %{
         name: queue_name,
         length: length,
         consumer_groups: groups,
         last_id: last_id
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @impl PolyQueue.Adapters.Behaviour
  def purge_queue(queue_name) do
    case redis_command(["DEL", queue_name]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl PolyQueue.Adapters.Behaviour
  def version do
    case redis_command(["INFO", "server"]) do
      {:ok, info} -> parse_version_from_info(info)
      {:error, reason} -> {:error, reason}
    end
  end

  @impl PolyQueue.Adapters.Behaviour
  def metadata do
    %{
      name: "Redis Streams",
      description: "Redis Streams message queue using redis-cli",
      protocol: "RESP",
      cli_tool: "redis-cli",
      features: [:publish, :subscribe, :consumer_groups, :persistence, :replay]
    }
  end

  # Server callbacks

  @impl GenServer
  def init(opts) do
    redis_host = Keyword.get(opts, :host, "localhost")
    redis_port = Keyword.get(opts, :port, 6379)

    {:ok,
     %{
       host: redis_host,
       port: redis_port
     }}
  end

  # Private functions

  defp redis_command(args) do
    case System.cmd("redis-cli", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {error, _} -> {:error, error}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp prepare_message(message) when is_map(message), do: message
  defp prepare_message(message) when is_binary(message), do: %{data: message}
  defp prepare_message(message), do: %{data: inspect(message)}

  defp create_consumer_group(stream, group) do
    # Try to create group, ignore if it already exists
    redis_command(["XGROUP", "CREATE", stream, group, "0", "MKSTREAM"])
  end

  defp get_stream_length(queue_name) do
    case redis_command(["XLEN", queue_name]) do
      {:ok, length} -> {:ok, String.to_integer(length)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_consumer_groups(queue_name) do
    case redis_command(["XINFO", "GROUPS", queue_name]) do
      {:ok, result} -> parse_groups_result(result)
      {:error, _} -> {:ok, []}
    end
  end

  defp get_last_id(queue_name) do
    case redis_command(["XREVRANGE", queue_name, "+", "-", "COUNT", "1"]) do
      {:ok, ""} -> {:ok, nil}
      {:ok, result} -> parse_last_id(result)
      {:error, _} -> {:ok, nil}
    end
  end

  defp parse_xread_result(result) do
    # Parse redis-cli XREADGROUP output
    # This is a simplified parser; production code would need more robust parsing
    messages = String.split(result, "\n", trim: true)
    {:ok, messages}
  end

  defp parse_scan_result(result) do
    # Parse SCAN output
    lines = String.split(result, "\n", trim: true)
    keys = Enum.drop(lines, 1)
    {:ok, keys}
  end

  defp parse_groups_result(result) do
    # Parse XINFO GROUPS output
    groups =
      result
      |> String.split("\n", trim: true)
      |> Enum.filter(&String.contains?(&1, "name"))
      |> Enum.map(&extract_group_name/1)

    {:ok, groups}
  end

  defp extract_group_name(line) do
    # Extract group name from XINFO output line
    line
    |> String.split()
    |> Enum.at(1, "")
  end

  defp parse_last_id(result) do
    case String.split(result, "\n", trim: true) do
      [id | _] -> {:ok, id}
      _ -> {:ok, nil}
    end
  end

  defp parse_version_from_info(info) do
    case Regex.run(~r/redis_version:(\S+)/, info) do
      [_, version] -> {:ok, version}
      _ -> {:error, "Could not parse version"}
    end
  end
end
