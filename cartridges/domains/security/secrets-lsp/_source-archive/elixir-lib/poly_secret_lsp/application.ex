# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolySecret.LSP.Application do
  @moduledoc false
  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    children = [
      # Adapter supervisor (manages all secrets backend adapter processes)
      {PolySecret.Adapters.Supervisor, []},

      # LSP server (GenLSP)
      {PolySecret.LSP.Server, []}
    ]

    opts = [strategy: :one_for_one, name: PolySecret.LSP.Supervisor]

    Logger.info("Starting PolySecret LSP server v#{PolySecret.LSP.version()}")

    Supervisor.start_link(children, opts)
  end
end
