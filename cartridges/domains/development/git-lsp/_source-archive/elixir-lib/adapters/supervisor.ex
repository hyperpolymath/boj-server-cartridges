# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyGit.Adapters.Supervisor do
  @moduledoc """
  Supervisor for Git forge adapter processes.

  Each adapter runs as an isolated GenServer. If an adapter crashes,
  only that adapter is affected - others continue running.
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl Supervisor
  def init(_init_arg) do
    children = [
      {PolyGit.Adapters.GitHub, []},
      {PolyGit.Adapters.GitLab, []},
      {PolyGit.Adapters.Gitea, []},
      {PolyGit.Adapters.Bitbucket, []}
    ]

    # one_for_one: if an adapter crashes, only restart that adapter
    Supervisor.init(children, strategy: :one_for_one)
  end
end
