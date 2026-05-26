# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyK8s.LSP.Handlers.Completion do
  @moduledoc """
  Auto-completion handler for Kubernetes manifests.

  Provides completions for:
  - Kubernetes resource types (Pod, Deployment, Service, etc.)
  - apiVersion values
  - Common fields (metadata, spec, status)
  - Label selectors
  """

  def handle(params, assigns) do
    uri = get_in(params, ["textDocument", "uri"])
    position = params["position"]

    doc = get_in(assigns, [:documents, uri])
    text = if doc, do: doc.text, else: ""

    context = get_line_context(text, position["line"], position["character"])

    completions = case detect_completion_type(context) do
      :api_version -> complete_api_versions()
      :kind -> complete_kinds()
      :field -> complete_fields(context)
      _ -> []
    end

    completions
  end

  defp get_line_context(text, line, character) do
    lines = String.split(text, "\n")
    current_line = Enum.at(lines, line, "")
    before_cursor = String.slice(current_line, 0, character)

    %{
      line: current_line,
      before_cursor: before_cursor,
      trimmed: String.trim_leading(current_line)
    }
  end

  defp detect_completion_type(context) do
    cond do
      String.contains?(context.before_cursor, "apiVersion:") -> :api_version
      String.contains?(context.before_cursor, "kind:") -> :kind
      String.match?(context.trimmed, ~r/^[a-zA-Z]+:/) -> :field
      true -> :none
    end
  end

  defp complete_api_versions do
    [
      "v1",
      "apps/v1",
      "batch/v1",
      "networking.k8s.io/v1",
      "rbac.authorization.k8s.io/v1",
      "autoscaling/v2",
      "storage.k8s.io/v1"
    ]
    |> Enum.map(&create_completion_item(&1, "value"))
  end

  defp complete_kinds do
    [
      "Pod", "Deployment", "Service", "ConfigMap", "Secret",
      "Namespace", "PersistentVolume", "PersistentVolumeClaim",
      "StatefulSet", "DaemonSet", "Job", "CronJob",
      "Ingress", "ServiceAccount", "Role", "RoleBinding"
    ]
    |> Enum.map(&create_completion_item(&1, "class"))
  end

  defp complete_fields(_context) do
    [
      "metadata", "spec", "status", "name", "namespace",
      "labels", "annotations", "replicas", "selector",
      "template", "containers", "image", "ports", "env"
    ]
    |> Enum.map(&create_completion_item(&1, "field"))
  end

  defp create_completion_item(label, kind_str) do
    kind = case kind_str do
      "value" -> 12      # Value
      "class" -> 7       # Class
      "field" -> 5       # Field
      _ -> 1             # Text
    end

    %{
      "label" => label,
      "kind" => kind,
      "detail" => kind_str,
      "insertText" => label
    }
  end
end
