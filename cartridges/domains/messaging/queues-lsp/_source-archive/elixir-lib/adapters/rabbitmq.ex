# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyQueue.Adapters.RabbitMQ do
  @moduledoc """
  RabbitMQ adapter for PolyQueue LSP.

  Uses rabbitmqctl and rabbitmqadmin CLI tools for queue management and operations.
  Supports standard RabbitMQ features including exchanges, bindings, and consumer management.
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
    case System.cmd("rabbitmqctl", ["status"], stderr_to_stdout: true) do
      {_output, 0} -> {:ok, true}
      _ -> {:ok, false}
    end
  rescue
    _ -> {:ok, false}
  end

  @impl PolyQueue.Adapters.Behaviour
  def publish(queue_name, message, opts \\ []) do
    exchange = Keyword.get(opts, :exchange, "")
    routing_key = Keyword.get(opts, :routing_key, queue_name)
    priority = Keyword.get(opts, :priority, :normal)

    message_body = prepare_message(message)

    args = [
      "publish",
      "exchange=#{exchange}",
      "routing_key=#{routing_key}",
      "payload=#{message_body}"
    ]

    args = if priority != :normal, do: args ++ ["properties={\"priority\":#{priority_value(priority)}}"], else: args

    case rabbitmq_admin_command(args) do
      {:ok, result} -> {:ok, extract_message_id(result)}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl PolyQueue.Adapters.Behaviour
  def subscribe(queue_name, opts \\ []) do
    count = Keyword.get(opts, :count, 10)
    ack = Keyword.get(opts, :ack, true)

    args = [
      "get",
      "queue=#{queue_name}",
      "count=#{count}",
      "ackmode=#{if ack, do: "ack_requeue_true", else: "ack_requeue_false"}",
      "encoding=auto"
    ]

    case rabbitmq_admin_command(args) do
      {:ok, result} -> parse_messages(result)
      {:error, reason} -> {:error, reason}
    end
  end

  @impl PolyQueue.Adapters.Behaviour
  def list_queues do
    case rabbitmq_ctl_command(["list_queues", "name", "--formatter", "json"]) do
      {:ok, result} -> parse_queue_list(result)
      {:error, reason} -> {:error, reason}
    end
  end

  @impl PolyQueue.Adapters.Behaviour
  def queue_status(queue_name) do
    args = ["list_queues", "name", "messages", "consumers", "--formatter", "json"]

    case rabbitmq_ctl_command(args) do
      {:ok, result} -> parse_queue_status(result, queue_name)
      {:error, reason} -> {:error, reason}
    end
  end

  @impl PolyQueue.Adapters.Behaviour
  def purge_queue(queue_name) do
    case rabbitmq_ctl_command(["purge_queue", queue_name]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl PolyQueue.Adapters.Behaviour
  def version do
    case rabbitmq_ctl_command(["version"]) do
      {:ok, version} -> {:ok, String.trim(version)}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl PolyQueue.Adapters.Behaviour
  def metadata do
    %{
      name: "RabbitMQ",
      description: "RabbitMQ message broker using rabbitmqctl/rabbitmqadmin",
      protocol: "AMQP 0-9-1",
      cli_tool: "rabbitmqctl/rabbitmqadmin",
      features: [:publish, :subscribe, :exchanges, :routing, :persistence, :priority]
    }
  end

  # Server callbacks

  @impl GenServer
  def init(opts) do
    rabbitmq_host = Keyword.get(opts, :host, "localhost")
    rabbitmq_port = Keyword.get(opts, :port, 5672)
    vhost = Keyword.get(opts, :vhost, "/")

    {:ok,
     %{
       host: rabbitmq_host,
       port: rabbitmq_port,
       vhost: vhost
     }}
  end

  # Private functions

  defp rabbitmq_ctl_command(args) do
    case System.cmd("rabbitmqctl", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {error, _} -> {:error, error}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp rabbitmq_admin_command(args) do
    case System.cmd("rabbitmqadmin", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {error, _} -> {:error, error}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp prepare_message(message) when is_map(message), do: Jason.encode!(message)
  defp prepare_message(message) when is_binary(message), do: message
  defp prepare_message(message), do: inspect(message)

  defp priority_value(:low), do: 1
  defp priority_value(:normal), do: 5
  defp priority_value(:high), do: 10

  defp extract_message_id(result) do
    # RabbitMQ doesn't return message IDs by default from rabbitmqadmin
    # Generate a timestamp-based ID
    "msg_#{System.system_time(:millisecond)}"
  end

  defp parse_messages(result) do
    try do
      messages =
        result
        |> Jason.decode!()
        |> Enum.map(& &1["payload"])

      {:ok, messages}
    rescue
      _ -> {:error, "Failed to parse messages"}
    end
  end

  defp parse_queue_list(result) do
    try do
      queues =
        result
        |> Jason.decode!()
        |> Enum.map(& &1["name"])

      {:ok, queues}
    rescue
      _ -> {:error, "Failed to parse queue list"}
    end
  end

  defp parse_queue_status(result, queue_name) do
    try do
      queues = Jason.decode!(result)

      case Enum.find(queues, &(&1["name"] == queue_name)) do
        nil ->
          {:error, "Queue not found"}

        queue ->
          {:ok,
           %{
             name: queue["name"],
             length: queue["messages"] || 0,
             consumer_groups: ["consumers: #{queue["consumers"] || 0}"],
             last_id: nil
           }}
      end
    rescue
      _ -> {:error, "Failed to parse queue status"}
    end
  end
end
