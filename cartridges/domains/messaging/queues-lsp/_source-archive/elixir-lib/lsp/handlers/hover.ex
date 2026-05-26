# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyQueue.LSP.Handlers.Hover do
  @moduledoc """
  Provides hover documentation for message queue systems.

  Shows:
  - Redis Streams command documentation
  - RabbitMQ configuration options
  - NATS configuration and subjects
  """

  def handle(params, assigns) do
    uri = get_in(params, ["textDocument", "uri"])
    position = params["position"]

    # Get document text from state
    doc = get_in(assigns, [:documents, uri])
    text = if doc, do: doc.text, else: ""

    # Get word at cursor position
    word = get_word_at_position(text, position["line"], position["character"])

    if word do
      # Get documentation based on queue type and word
      docs = case assigns.detected_queue do
        :redis_streams -> get_redis_docs(word)
        :rabbitmq -> get_rabbitmq_docs(word)
        :nats -> get_nats_docs(word)
        _ -> get_generic_docs(word)
      end

      if docs do
        %{
          "contents" => %{
            "kind" => "markdown",
            "value" => docs
          }
        }
      else
        nil
      end
    else
      nil
    end
  end

  # Extract word at position
  defp get_word_at_position(text, line, character) do
    lines = String.split(text, "\n")
    current_line = Enum.at(lines, line, "")

    # Find word boundaries (including hyphens for config keys)
    before = String.slice(current_line, 0, character) |> String.reverse()
    after_text = String.slice(current_line, character, String.length(current_line))

    start = Regex.run(~r/^[a-zA-Z0-9_-]*/, before) |> List.first() |> String.reverse()
    end_part = Regex.run(~r/^[a-zA-Z0-9_-]*/, after_text) |> List.first()

    word = start <> end_part
    if String.length(word) > 0, do: word, else: nil
  end

  # Redis Streams documentation
  defp get_redis_docs(word) do
    docs = %{
      "XADD" => "**XADD key ID field value [field value ...]** - Add entry to stream\n\nAppends new entry to the stream. ID can be `*` for auto-generation.\n\nExample: `XADD mystream * sensor-id 1234 temperature 19.8`",
      "XREAD" => "**XREAD [COUNT count] [BLOCK milliseconds] STREAMS key [key ...] ID [ID ...]** - Read from streams\n\nReads entries from one or more streams.\n\nExample: `XREAD COUNT 2 STREAMS mystream 0`",
      "XREADGROUP" => "**XREADGROUP GROUP group consumer [COUNT count] [BLOCK milliseconds] STREAMS key [key ...] ID [ID ...]** - Read as consumer group\n\nReads entries as part of a consumer group.",
      "XGROUP" => "**XGROUP subcommand** - Manage consumer groups\n\nSubcommands: CREATE, SETID, DESTROY, DELCONSUMER",
      "XACK" => "**XACK key group ID [ID ...]** - Acknowledge processed messages\n\nMarks messages as processed in a consumer group.",
      "XPENDING" => "**XPENDING key group** - Get pending messages\n\nReturns information about pending messages in a consumer group.",
      "XLEN" => "**XLEN key** - Get stream length\n\nReturns the number of entries in the stream.",
      "XRANGE" => "**XRANGE key start end [COUNT count]** - Get range of entries\n\nReturns entries between start and end IDs.",
      "XTRIM" => "**XTRIM key strategy** - Trim stream\n\nRemoves entries from the stream. Strategies: MAXLEN, MINID",
      "STREAMS" => "**STREAMS** - Specify stream keys and IDs\n\nUsed with XREAD/XREADGROUP to specify streams and starting positions.",
      "COUNT" => "**COUNT** - Limit number of entries\n\nLimits the number of entries returned.",
      "BLOCK" => "**BLOCK milliseconds** - Block for timeout\n\nBlocks connection until new entries arrive or timeout."
    }

    Map.get(docs, String.upcase(word))
  end

  # RabbitMQ documentation
  defp get_rabbitmq_docs(word) do
    docs = %{
      "listeners" => "**listeners** - Network listeners configuration\n\nDefines network interfaces and ports for connections.",
      "tcp_listeners" => "**tcp_listeners** - TCP listener ports\n\nPort(s) for AMQP connections. Default: 5672",
      "ssl_listeners" => "**ssl_listeners** - SSL/TLS listener ports\n\nPort(s) for secure AMQP connections.",
      "default_user" => "**default_user** - Default username\n\nDefault user created on first startup.",
      "default_pass" => "**default_pass** - Default password\n\nPassword for default user.",
      "default_vhost" => "**default_vhost** - Default virtual host\n\nDefault vhost created on startup. Default: /",
      "disk_free_limit" => "**disk_free_limit** - Disk free space limit\n\nMinimum free disk space before flow control.",
      "vm_memory_high_watermark" => "**vm_memory_high_watermark** - Memory threshold\n\nMemory threshold for flow control. Default: 0.4",
      "durable" => "**durable** - Queue durability\n\nIf true, queue survives broker restart.",
      "auto_delete" => "**auto_delete** - Auto-delete flag\n\nIf true, queue is deleted when last consumer disconnects.",
      "exclusive" => "**exclusive** - Exclusive queue\n\nIf true, queue is used by only one connection.",
      "x-message-ttl" => "**x-message-ttl** - Message time-to-live\n\nTime in milliseconds before messages expire.",
      "x-max-length" => "**x-max-length** - Maximum queue length\n\nMaximum number of messages in queue.",
      "x-dead-letter-exchange" => "**x-dead-letter-exchange** - Dead letter exchange\n\nExchange to send rejected or expired messages.",
      "direct" => "**direct** - Direct exchange type\n\nRoutes messages with exact routing key match.",
      "topic" => "**topic** - Topic exchange type\n\nRoutes messages using pattern matching on routing key.",
      "fanout" => "**fanout** - Fanout exchange type\n\nBroadcasts messages to all bound queues.",
      "headers" => "**headers** - Headers exchange type\n\nRoutes based on message header attributes."
    }

    Map.get(docs, word)
  end

  # NATS documentation
  defp get_nats_docs(word) do
    docs = %{
      "port" => "**port** - Client connection port\n\nPort for client connections. Default: 4222",
      "host" => "**host** - Host address\n\nHost address to bind to. Default: 0.0.0.0",
      "client_advertise" => "**client_advertise** - Advertised client URL\n\nURL advertised to clients for connection.",
      "http" => "**http** - HTTP monitoring port\n\nPort for HTTP monitoring endpoint.",
      "cluster" => "**cluster** - Cluster configuration\n\nConfiguration for NATS cluster mode.",
      "jetstream" => "**jetstream** - JetStream configuration\n\nEnables and configures JetStream persistence.",
      "accounts" => "**accounts** - Multi-tenancy accounts\n\nDefines accounts for multi-tenancy.",
      "authorization" => "**authorization** - Authorization settings\n\nUser and permission configuration.",
      "subscribe" => "**subscribe(subject, callback)** - Subscribe to subject\n\nSubscribes to messages on a subject.",
      "publish" => "**publish(subject, data)** - Publish message\n\nPublishes a message to a subject.",
      "request" => "**request(subject, data, timeout)** - Request-reply\n\nSends a request and waits for reply.",
      "reply" => "**reply(subject, data)** - Send reply\n\nSends a reply to a request.",
      "stream" => "**stream** - JetStream stream\n\nPersistent message stream in JetStream.",
      "consumer" => "**consumer** - JetStream consumer\n\nConsumer for processing stream messages."
    }

    Map.get(docs, word)
  end

  # Generic queue documentation
  defp get_generic_docs(word) do
    docs = %{
      "publish" => "**publish** - Send message to queue\n\nPublishes a message to the queue system.",
      "subscribe" => "**subscribe** - Receive messages\n\nSubscribes to receive messages from a queue.",
      "consume" => "**consume** - Process messages\n\nConsumes messages from a queue.",
      "ack" => "**ack** - Acknowledge message\n\nAcknowledges successful message processing.",
      "nack" => "**nack** - Negative acknowledgement\n\nRejects a message, may trigger redelivery."
    }

    Map.get(docs, word)
  end
end
