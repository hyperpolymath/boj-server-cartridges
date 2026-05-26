# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyCloud.LSP.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start adapter supervisor (manages all cloud provider adapters)
      PolyCloud.Adapters.Supervisor,
      # Start LSP server
      {PolyCloud.LSP.Server, []}
    ]

    opts = [strategy: :one_for_one, name: PolyCloud.LSP.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
