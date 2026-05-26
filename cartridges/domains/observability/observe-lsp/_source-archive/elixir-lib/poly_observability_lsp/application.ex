# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyObservability.LSP.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start adapter GenServers
      PolyObservability.Adapters.Prometheus,
      PolyObservability.Adapters.Grafana,
      PolyObservability.Adapters.Loki,
      PolyObservability.Adapters.Jaeger
    ]

    opts = [strategy: :one_for_one, name: PolyObservability.LSP.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
