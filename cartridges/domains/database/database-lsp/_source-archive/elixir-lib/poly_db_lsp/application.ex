# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyDB.LSP.Application do
  @moduledoc """
  Application module for PolyDB LSP server.

  Starts the LSP server and all database adapters under a supervision tree.
  """

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting PolyDB LSP server")

    children = [
      # Database adapters
      PolyDB.Adapters.PostgreSQL,
      PolyDB.Adapters.MongoDB,
      PolyDB.Adapters.Redis,
      PolyDB.Adapters.Neo4j,
      PolyDB.Adapters.MySQL,
      PolyDB.Adapters.SQLite

      # LSP server will be added here
      # {PolyDB.LSP.Server, []}
    ]

    opts = [strategy: :one_for_one, name: PolyDB.LSP.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
