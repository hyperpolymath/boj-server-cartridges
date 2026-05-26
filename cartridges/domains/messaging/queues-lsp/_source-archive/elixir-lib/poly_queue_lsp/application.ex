# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyQueue.LSP.Application do
  @moduledoc """
  OTP Application for PolyQueue LSP.

  Starts a supervision tree with all message queue adapters.
  Each adapter is isolated, so failures don't cascade.
  """

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    children = [
      # Start adapters under supervision
      {PolyQueue.Adapters.RedisStreams, []},
      {PolyQueue.Adapters.RabbitMQ, []},
      {PolyQueue.Adapters.NATS, []}
    ]

    opts = [strategy: :one_for_one, name: PolyQueue.LSP.Supervisor]
    Logger.info("Starting PolyQueue LSP v#{PolyQueue.LSP.version()}")
    Supervisor.start_link(children, opts)
  end
end
