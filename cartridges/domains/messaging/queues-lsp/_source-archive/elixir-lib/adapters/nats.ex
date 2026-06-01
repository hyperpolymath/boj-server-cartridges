# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyQueue.Adapters.NATS do
  @moduledoc """
  NATS adapter for PolyQueue LSP.

  Uses the nats CLI tool for NATS and NATS JetStream operations.
  Supports both core NATS (pub/sub) and JetStream (persistence, replay).
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
    case System.cmd("nats", ["--version"], stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.contains?(output, "nats")}
      _ -> {:ok, false}
    end
  rescue
    _ -> {:ok, false}
  end

  @impl PolyQueue.Adapters.Behaviour
  def publish(queue_name, message, opts \\ []) do
    stream = Keyword.get(opts, :stream, false)
    headers = Keyword.get(opts, :headers, %{})

    message_body = prepare_message(message)

    args =
      if stream do
        ["stream", "pub", queue_name, message_body]
      else
        ["pub", queue_name, message_body]
      end

    args = add_headers(args, headers)

    case nats_command(args) do
      {:ok, result} -> {:ok, extract_message_id(result)}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl PolyQueue.Adapters.Behaviour
  def subscribe(queue_name, opts \\ []) do
    stream = Keyword.get(opts, :stream, false)
    count = Keyword.get(opts, :count, 10)
    consumer = Keyword.get(opts, :consumer, "default-consumer")
    durable = Keyword.get(opts, :durable, false)

    args =
      if stream do
        base = ["stream", "sub", queue_name, "--count", to_string(count)]

        base =
          if durable do
            base ++ ["--consumer", consumer, "--durable"]
          else
            base
          end

        base
      else
        ["sub", queue_name, "--count", to_string(count)]
      end

    case nats_command(args) do
      {:ok, result} -> parse_messages(result)
      {:error, reason} -> {:error, reason}
    end
  end

  @impl PolyQueue.Adapters.Behaviour
  def list_queues do
    # For JetStream, list streams
    case nats_command(["stream", "list", "--json"]) do
      {:ok, result} -> parse_stream_list(result)
      {:error, _} -> {:ok, []}
    end
  end

  @impl PolyQueue.Adapters.Behaviour
  def queue_status(queue_name) do
    case nats_command(["stream", "info", queue_name, "--json"]) do
      {:ok, result} -> parse_stream_info(result, queue_name)
      {:error, reason} -> {:error, reason}
    end
  end

  @impl PolyQueue.Adapters.Behaviour
  def purge_queue(queue_name) do
    case nats_command(["stream", "purge", queue_name, "--force"]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl PolyQueue.Adapters.Behaviour
  def version do
    case nats_command(["--version"]) do
      {:ok, version} ->
        version_str =
          version
          |> String.trim()
          |> String.replace("nats version ", "")

        {:ok, version_str}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl PolyQueue.Adapters.Behaviour
  def metadata do
    %{
      name: "NATS",
      description: "NATS messaging system with JetStream support",
      protocol: "NATS Protocol",
      cli_tool: "nats",
      features: [:publish, :subscribe, :jetstream, :persistence, :replay, :at_least_once]
    }
  end

  # Server callbacks

  @impl GenServer
  def init(opts) do
    nats_server = Keyword.get(opts, :server, "nats://localhost:4222")

    {:ok,
     %{
       server: nats_server
     }}
  end

  # Private functions

  defp nats_command(args) do
    case System.cmd("nats", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {error, _} -> {:error, error}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp prepare_message(message) when is_map(message), do: Jason.encode!(message)
  defp prepare_message(message) when is_binary(message), do: message
  defp prepare_message(message), do: inspect(message)

  defp add_headers(args, headers) when headers == %{}, do: args

  defp add_headers(args, headers) do
    header_args =
      Enum.flat_map(headers, fn {k, v} ->
        ["--header", "#{k}:#{v}"]
      end)

    args ++ header_args
  end

  defp extract_message_id(result) do
    # Try to extract sequence number from JetStream publish result
    case Regex.run(~r/sequence: (\d+)/, result) do
      [_, seq] -> "seq_#{seq}"
      _ -> "msg_#{System.system_time(:millisecond)}"
    end
  end

  defp parse_messages(result) do
    # Parse nats sub output
    messages =
      result
      |> String.split("\n", trim: true)
      |> Enum.filter(&String.starts_with?(&1, "[#"))
      |> Enum.map(&extract_message_body/1)

    {:ok, messages}
  end

  defp extract_message_body(line) do
    # Extract message body from "[#N] Received on 'subject': message"
    case String.split(line, "': ", parts: 2) do
      [_, body] -> body
      _ -> line
    end
  end

  defp parse_stream_list(result) do
    try do
      data = Jason.decode!(result)
      streams = data["streams"] || []
      names = Enum.map(streams, & &1["name"])
      {:ok, names}
    rescue
      _ -> {:ok, []}
    end
  end

  defp parse_stream_info(result, queue_name) do
    try do
      info = Jason.decode!(result)
      state = info["state"] || %{}

      {:ok,
       %{
         name: queue_name,
         length: state["messages"] || 0,
         consumer_groups: get_consumers(info),
         last_id: state["last_seq"] |> to_string()
       }}
    rescue
      _ -> {:error, "Failed to parse stream info"}
    end
  end

  defp get_consumers(info) do
    case info["consumers"] do
      nil -> []
      consumers when is_list(consumers) -> Enum.map(consumers, & &1["name"])
      _ -> []
    end
  end
end
