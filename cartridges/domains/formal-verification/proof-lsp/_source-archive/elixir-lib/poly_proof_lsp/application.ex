# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyProof.LSP.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Adapter supervisor - each proof assistant runs as isolated process
      PolyProof.Adapters.Supervisor,

      # LSP server
      {PolyProof.LSP.Server, []}
    ]

    opts = [strategy: :one_for_one, name: PolyProof.LSP.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
