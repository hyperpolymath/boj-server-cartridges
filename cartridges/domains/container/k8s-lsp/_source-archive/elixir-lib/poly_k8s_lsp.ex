# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyK8s.LSP do
  @moduledoc """
  PolyK8s LSP - Language Server Protocol for Kubernetes orchestration.

  Provides IDE integration for kubectl, Helm, and Kustomize with features like:

  - Auto-detection of K8s tools in projects
  - Command execution (apply, get, describe, logs, rollout)
  - YAML manifest validation
  - Auto-completion for Kubernetes resources
  - Diagnostics and hover documentation
  """

  @doc """
  Detect which K8s tools are available in the given project.

  Returns a list of detected tools as atoms: `:kubectl`, `:helm`, `:kustomize`.
  """
  def detect_tools(project_path) do
    adapters = [
      {PolyK8s.Adapters.Kubectl, :kubectl},
      {PolyK8s.Adapters.Helm, :helm},
      {PolyK8s.Adapters.Kustomize, :kustomize}
    ]

    Enum.reduce(adapters, [], fn {adapter, name}, acc ->
      case adapter.detect(project_path) do
        {:ok, true} -> [name | acc]
        _ -> acc
      end
    end)
  end
end
