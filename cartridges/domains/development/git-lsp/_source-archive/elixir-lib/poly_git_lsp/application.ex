# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyGit.LSP.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    children = [
      # Start the adapter supervisor
      PolyGit.Adapters.Supervisor,
      # Start the LSP server
      {PolyGit.LSP.Server, []}
    ]

    opts = [strategy: :one_for_one, name: PolyGit.LSP.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
