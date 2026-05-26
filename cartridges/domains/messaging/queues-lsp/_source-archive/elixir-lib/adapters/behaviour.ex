# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyQueue.Adapters.Behaviour do
  @moduledoc """
  Behaviour defining the contract for message queue adapters.

  Each adapter implements this behaviour to provide a consistent interface
  for detecting, publishing, subscribing, and managing message queues.

  ## Example

      defmodule PolyQueue.Adapters.RedisStreams do
        use GenServer
        @behaviour PolyQueue.Adapters.Behaviour

        @impl true
        def detect() do
          case System.cmd("redis-cli", ["--version"]) do
            {output, 0} -> {:ok, String.trim(output) != ""}
            _ -> {:ok, false}
          end
        end

        @impl true
        def publish(queue_name, message, opts) do
          # Publish to Redis Stream
        end
      end
  """

  @type queue_name :: String.t()
  @type message :: map() | String.t()
  @type subscribe_opts :: keyword()
  @type publish_opts :: keyword()
  @type queue_info :: %{
          name: String.t(),
          length: non_neg_integer(),
          consumer_groups: [String.t()],
          last_id: String.t() | nil
        }

  @doc """
  Detect if this message queue system is available.

  Returns `{:ok, true}` if the CLI tool is installed and accessible, `{:ok, false}` otherwise.
  """
  @callback detect() :: {:ok, boolean()} | {:error, String.t()}

  @doc """
  Publish a message to a queue.

  ## Options

  - `:priority` - Message priority (`:low`, `:normal`, `:high`)
  - `:ttl` - Time-to-live in milliseconds
  - `:headers` - Additional message headers (map)
  - `:message_id` - Custom message ID (optional)
  """
  @callback publish(queue_name, message, publish_opts) ::
              {:ok, String.t()} | {:error, String.t()}

  @doc """
  Subscribe to a queue and receive messages.

  Returns a stream or list of messages. Implementation may use GenStage or
  a callback function depending on the adapter.

  ## Options

  - `:consumer_group` - Consumer group name
  - `:consumer_name` - Consumer name within group
  - `:count` - Maximum number of messages to retrieve
  - `:block` - Block time in milliseconds
  - `:start_id` - Start reading from this message ID
  """
  @callback subscribe(queue_name, subscribe_opts) ::
              {:ok, Enumerable.t()} | {:error, String.t()}

  @doc """
  List all available queues.

  Returns a list of queue names.
  """
  @callback list_queues() :: {:ok, [String.t()]} | {:error, String.t()}

  @doc """
  Get queue status and statistics.

  Returns detailed information about a specific queue.
  """
  @callback queue_status(queue_name) :: {:ok, queue_info} | {:error, String.t()}

  @doc """
  Purge (empty) a queue.

  Removes all messages from the specified queue.
  """
  @callback purge_queue(queue_name) :: :ok | {:error, String.t()}

  @doc """
  Get message queue system version.
  """
  @callback version() :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Get message queue system metadata (name, description, capabilities).
  """
  @callback metadata() :: %{
              name: String.t(),
              description: String.t(),
              protocol: String.t(),
              cli_tool: String.t(),
              features: [atom()]
            }
end
