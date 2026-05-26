# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyProof.Adapters.Supervisor do
  @moduledoc """
  Supervisor for proof assistant adapters.

  Each adapter runs as an isolated GenServer. If one adapter crashes
  (e.g., Coq), it doesn't affect others (e.g., Lean).
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      PolyProof.Adapters.Coq,
      PolyProof.Adapters.Lean,
      PolyProof.Adapters.Isabelle,
      PolyProof.Adapters.Agda
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
