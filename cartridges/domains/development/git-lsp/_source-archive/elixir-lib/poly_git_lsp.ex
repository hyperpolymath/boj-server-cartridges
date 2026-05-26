# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyGit.LSP do
  @moduledoc """
  PolyGit LSP - Language Server Protocol for Git forge management.

  Provides IDE integration for GitHub, GitLab, Gitea, and Bitbucket operations.
  """

  @doc """
  Detect which Git forge is used by the project.

  Returns a list of detected forges.
  """
  def detect_forge(project_path) do
    adapters = [
      PolyGit.Adapters.GitHub,
      PolyGit.Adapters.GitLab,
      PolyGit.Adapters.Gitea,
      PolyGit.Adapters.Bitbucket
    ]

    adapters
    |> Enum.map(fn adapter ->
      case adapter.detect(project_path) do
        {:ok, true} -> {adapter, true}
        _ -> {adapter, false}
      end
    end)
    |> Enum.filter(fn {_adapter, detected} -> detected end)
    |> Enum.map(fn {adapter, _} -> adapter end)
  end
end
