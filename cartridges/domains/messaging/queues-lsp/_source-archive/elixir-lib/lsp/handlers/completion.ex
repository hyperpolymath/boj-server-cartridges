# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyQueue.LSP.Handlers.Completion do
  @moduledoc """
  Provides auto-completion for message queue systems.

  Supports:
  - Redis Streams commands and configuration
  - RabbitMQ configuration and exchange types
  - NATS configuration and subjects
  """

  def handle(params, assigns) do
    uri = get_in(params, ["textDocument", "uri"])
    position = params["position"]

    # Get document text from state
    doc = get_in(assigns, [:documents, uri])
    text = if doc, do: doc.text, else: ""

    # Get line and character position
    line = position["line"]
    character = position["character"]

    # Get context around cursor
    context = get_line_context(text, line, character)

    # Provide completions based on context and detected queue
    completions = case assigns.detected_queue do
      :redis_streams -> complete_redis_streams(context)
      :rabbitmq -> complete_rabbitmq(context, uri)
      :nats -> complete_nats(context, uri)
      _ -> complete_generic(context)
    end

    completions
  end

  # Extract line context around cursor
  defp get_line_context(text, line, character) do
    lines = String.split(text, "\n")
    current_line = Enum.at(lines, line, "")
    before_cursor = String.slice(current_line, 0, character)

    %{
      line: current_line,
      before_cursor: before_cursor,
      trigger: get_trigger(before_cursor)
    }
  end

  # Detect completion trigger
  defp get_trigger(text) do
    cond do
      String.match?(text, ~r/XADD\s+\w*$/) -> :redis_stream_key
      String.match?(text, ~r/XREAD\s+\w*$/) -> :redis_read_options
      String.match?(text, ~r/exchange\s*:\s*$/) -> :rabbitmq_exchange
      String.match?(text, ~r/type\s*:\s*$/) -> :rabbitmq_type
      String.match?(text, ~r/subject\s*:\s*$/) -> :nats_subject
      true -> :none
    end
  end

  # Redis Streams completions
  defp complete_redis_streams(context) do
    case context.trigger do
      :redis_stream_key ->
        ["STREAMS", "COUNT", "BLOCK", "MAXLEN"]
        |> Enum.map(&create_completion_item(&1, "keyword"))

      :redis_read_options ->
        ["COUNT", "BLOCK", "STREAMS"]
        |> Enum.map(&create_completion_item(&1, "keyword"))

      _ ->
        # Redis Streams commands
        [
          "XADD", "XREAD", "XREADGROUP", "XGROUP",
          "XACK", "XPENDING", "XLEN", "XRANGE",
          "XREVRANGE", "XTRIM", "XINFO"
        ]
        |> Enum.map(&create_completion_item(&1, "function"))
    end
  end

  # RabbitMQ completions
  defp complete_rabbitmq(context, uri) do
    case context.trigger do
      :rabbitmq_exchange ->
        ["direct", "topic", "fanout", "headers"]
        |> Enum.map(&create_completion_item(&1, "enum"))

      :rabbitmq_type ->
        ["queue", "exchange", "binding"]
        |> Enum.map(&create_completion_item(&1, "enum"))

      _ ->
        if String.ends_with?(uri, ".conf") do
          # RabbitMQ configuration keys
          [
            "listeners", "tcp_listeners", "ssl_listeners",
            "default_user", "default_pass", "default_vhost",
            "disk_free_limit", "vm_memory_high_watermark"
          ]
          |> Enum.map(&create_completion_item(&1, "field"))
        else
          # RabbitMQ queue options
          [
            "durable", "auto_delete", "exclusive", "arguments",
            "x-message-ttl", "x-max-length", "x-dead-letter-exchange"
          ]
          |> Enum.map(&create_completion_item(&1, "field"))
        end
    end
  end

  # NATS completions
  defp complete_nats(context, uri) do
    case context.trigger do
      :nats_subject ->
        ["events", "commands", "requests", "responses"]
        |> Enum.map(&create_completion_item(&1, "value"))

      _ ->
        if String.ends_with?(uri, ".conf") do
          # NATS configuration keys
          [
            "port", "host", "client_advertise", "http",
            "cluster", "jetstream", "accounts", "authorization"
          ]
          |> Enum.map(&create_completion_item(&1, "field"))
        else
          # NATS subject patterns
          [
            "subscribe", "publish", "request", "reply",
            "jetstream", "stream", "consumer"
          ]
          |> Enum.map(&create_completion_item(&1, "function"))
        end
    end
  end

  # Generic queue completions
  defp complete_generic(context) do
    case context.trigger do
      :none ->
        ["publish", "subscribe", "consume", "ack", "nack"]
        |> Enum.map(&create_completion_item(&1, "function"))

      _ ->
        []
    end
  end

  # Create LSP completion item
  defp create_completion_item(label, kind_str) do
    kind = case kind_str do
      "function" -> 3    # Function
      "field" -> 5       # Field
      "keyword" -> 14    # Keyword
      "enum" -> 13       # Enum
      "value" -> 12      # Value
      _ -> 1             # Text
    end

    %{
      "label" => label,
      "kind" => kind,
      "detail" => "#{kind_str}",
      "insertText" => label
    }
  end
end
