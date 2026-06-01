# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolySSG.Adapters.Supervisor do
  @moduledoc """
  Supervises all SSG adapter processes.

  Each adapter runs as an isolated GenServer. If one crashes, it's restarted
  automatically without affecting other adapters.
  """
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Rust SSGs
      {PolySSG.Adapters.Zola, []},
      {PolySSG.Adapters.MdBook, []},

      # Haskell SSGs
      {PolySSG.Adapters.Hakyll, []},

      # Julia SSGs
      {PolySSG.Adapters.Franklin, []},

      # Go SSGs
      {PolySSG.Adapters.Hugo, []},

      # Ruby SSGs
      {PolySSG.Adapters.Jekyll, []}

      # ... 54+ more adapters to add
    ]

    # :one_for_one strategy: if a child crashes, only restart that child
    Supervisor.init(children, strategy: :one_for_one)
  end
end
