# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyCloud.Adapters.Supervisor do
  @moduledoc """
  Supervisor for cloud provider adapters.

  Each adapter runs as an isolated GenServer process. If one adapter crashes,
  it's automatically restarted without affecting other adapters.
  """
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      {PolyCloud.Adapters.AWS, []},
      {PolyCloud.Adapters.GCP, []},
      {PolyCloud.Adapters.Azure, []},
      {PolyCloud.Adapters.DigitalOcean, []}
    ]

    # :one_for_one means if one child crashes, only that child is restarted
    Supervisor.init(children, strategy: :one_for_one)
  end
end
