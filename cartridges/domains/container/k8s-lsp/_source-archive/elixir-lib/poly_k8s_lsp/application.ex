# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyK8s.LSP.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the adapter supervisor
      PolyK8s.Adapters.Supervisor
      # TODO: Start the LSP server
      # {PolyK8s.LSP.Server, []}
    ]

    opts = [strategy: :one_for_one, name: PolyK8s.LSP.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
