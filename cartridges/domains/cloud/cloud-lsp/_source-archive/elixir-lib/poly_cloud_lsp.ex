# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyCloud.LSP do
  @moduledoc """
  PolyCloud LSP - Language Server Protocol for multi-cloud provider management.

  Provides IDE integration for AWS, GCP, Azure, and DigitalOcean deployments.
  """

  @doc """
  Detect which cloud providers are configured in a project directory.

  ## Example

      PolyCloud.LSP.detect_providers("/path/to/project")
      # => [:aws, :gcp]
  """
  def detect_providers(project_path) do
    adapters = [
      {:aws, PolyCloud.Adapters.AWS},
      {:gcp, PolyCloud.Adapters.GCP},
      {:azure, PolyCloud.Adapters.Azure},
      {:digitalocean, PolyCloud.Adapters.DigitalOcean}
    ]

    adapters
    |> Enum.filter(fn {_name, adapter} ->
      case adapter.detect(project_path) do
        {:ok, true} -> true
        _ -> false
      end
    end)
    |> Enum.map(fn {name, _adapter} -> name end)
  end
end
