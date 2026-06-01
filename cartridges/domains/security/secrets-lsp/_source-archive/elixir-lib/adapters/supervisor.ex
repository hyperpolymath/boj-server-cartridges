# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolySecret.Adapters.Supervisor do
  @moduledoc """
  Supervisor for secrets management adapters.

  Each adapter runs as an isolated GenServer process. If one adapter crashes,
  it doesn't affect others, and the supervisor automatically restarts it.
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {PolySecret.Adapters.Vault, []},
      {PolySecret.Adapters.SOPS, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
