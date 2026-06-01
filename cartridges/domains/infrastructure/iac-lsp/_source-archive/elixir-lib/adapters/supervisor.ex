# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyIaC.Adapters.Supervisor do
  @moduledoc """
  Supervisor for all IaC adapter processes.

  Each adapter runs as an isolated GenServer under this supervisor.
  If an adapter crashes, it's automatically restarted without affecting other adapters.
  """
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {PolyIaC.Adapters.OpenTofu, []},
      {PolyIaC.Adapters.Pulumi, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
