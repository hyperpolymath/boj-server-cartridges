# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolySSG.LSP.Application do
  @moduledoc false
  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    children = [
      # Adapter supervisor (manages all SSG adapter processes)
      {PolySSG.Adapters.Supervisor, []},

      # LSP server (GenLSP)
      {PolySSG.LSP.Server, []}
    ]

    opts = [strategy: :one_for_one, name: PolySSG.LSP.Supervisor]

    Logger.info("Starting PolySSG LSP server v#{PolySSG.LSP.version()}")

    Supervisor.start_link(children, opts)
  end
end
