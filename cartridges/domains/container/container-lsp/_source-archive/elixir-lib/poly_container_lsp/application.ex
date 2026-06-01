# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyContainer.LSP.Application do
  @moduledoc """
  Application entry point for PolyContainer LSP.

  Starts the adapter supervisor and LSP server.
  """
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PolyContainer.Adapters.Supervisor
      # {PolyContainer.LSP.Server, []} # TODO: Add when LSP server is implemented
    ]

    opts = [strategy: :one_for_one, name: PolyContainer.LSP.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
