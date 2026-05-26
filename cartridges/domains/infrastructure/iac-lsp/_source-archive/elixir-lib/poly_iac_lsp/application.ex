# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyIaC.LSP.Application do
  @moduledoc false
  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    children = [
      # Adapter supervisor (manages all IaC adapter processes)
      {PolyIaC.Adapters.Supervisor, []},

      # LSP server (GenLSP) - commented out until LSP server is implemented
      # {PolyIaC.LSP.Server, []}
    ]

    opts = [strategy: :one_for_one, name: PolyIaC.LSP.Supervisor]

    Logger.info("Starting PolyIaC LSP server v#{PolyIaC.LSP.version()}")

    Supervisor.start_link(children, opts)
  end
end
