# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyContainer.Adapters.Supervisor do
  @moduledoc """
  Supervisor for container runtime adapters.

  Each adapter runs as an isolated GenServer process, providing fault
  tolerance and automatic restart on crashes.
  """
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {PolyContainer.Adapters.Nerdctl, []},
      {PolyContainer.Adapters.Podman, []},
      {PolyContainer.Adapters.Docker, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
