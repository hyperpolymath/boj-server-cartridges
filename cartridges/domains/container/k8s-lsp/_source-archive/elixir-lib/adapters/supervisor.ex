# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyK8s.Adapters.Supervisor do
  @moduledoc """
  Supervisor for all K8s tool adapters.

  Each adapter runs as an isolated GenServer process with automatic
  fault recovery via BEAM supervision trees.
  """
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      {PolyK8s.Adapters.Kubectl, []},
      {PolyK8s.Adapters.Helm, []},
      {PolyK8s.Adapters.Kustomize, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
