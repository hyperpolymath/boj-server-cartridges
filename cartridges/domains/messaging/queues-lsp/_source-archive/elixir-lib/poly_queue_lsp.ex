# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyQueue.LSP do
  @moduledoc """
  Language Server Protocol implementation for message queue management.

  Provides IDE integration for:
  - Auto-completion (queue names, consumer groups, message formats)
  - Diagnostics (connection errors, queue issues)
  - Hover documentation (queue statistics, consumer info)
  - Custom commands (publish, subscribe, purge, list queues)

  ## Architecture

  Each message queue adapter (Redis Streams, RabbitMQ, NATS) runs as an isolated
  GenServer process under a supervision tree. Crashes in one adapter don't affect
  others. The BEAM VM handles concurrency automatically for managing multiple
  queue systems in parallel.

  ## Supported Message Queue Systems

  - **Redis Streams** - Using redis-cli
  - **RabbitMQ** - Using rabbitmqctl/rabbitmqadmin
  - **NATS** - Using nats CLI (with JetStream support)
  """

  @version Mix.Project.config()[:version]

  @doc "Returns the current version"
  def version, do: @version
end
