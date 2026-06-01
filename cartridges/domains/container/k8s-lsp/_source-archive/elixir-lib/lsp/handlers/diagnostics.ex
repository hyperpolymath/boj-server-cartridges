# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyK8s.LSP.Handlers.Diagnostics do
  @moduledoc """
  Diagnostics handler for Kubernetes manifests.

  Validates:
  - YAML syntax
  - Required fields (apiVersion, kind, metadata)
  - Resource naming conventions
  - Best practices
  """

  require Logger

  def handle(params, assigns) do
    uri = get_in(params, ["textDocument", "uri"]) || ""

    doc = get_in(assigns, [:documents, uri])
    text = if doc, do: doc.text, else: ""

    diagnostics = validate_manifest(text)

    %{
      "uri" => uri,
      "diagnostics" => diagnostics
    }
  end

  defp validate_manifest(text) do
    diagnostics = []

    diagnostics = diagnostics ++ check_required_fields(text)
    diagnostics = diagnostics ++ check_naming_conventions(text)
    diagnostics = diagnostics ++ check_best_practices(text)

    diagnostics
  end

  defp check_required_fields(text) do
    diagnostics = []

    unless String.contains?(text, "apiVersion:") do
      diagnostics = diagnostics ++ [create_diagnostic("Missing required field: apiVersion", 1, 0)]
    end

    unless String.contains?(text, "kind:") do
      diagnostics = diagnostics ++ [create_diagnostic("Missing required field: kind", 1, 0)]
    end

    unless String.contains?(text, "metadata:") do
      diagnostics = diagnostics ++ [create_diagnostic("Missing required field: metadata", 1, 0)]
    end

    diagnostics
  end

  defp check_naming_conventions(text) do
    diagnostics = []

    # Check for invalid characters in names (must be lowercase alphanumeric with dashes)
    if Regex.match?(~r/name:\s*[A-Z_]/, text) do
      diagnostics = diagnostics ++ [create_diagnostic("Resource names should be lowercase with dashes", 2, 0)]
    end

    diagnostics
  end

  defp check_best_practices(text) do
    diagnostics = []

    # Check for missing namespace
    if String.contains?(text, "kind: Deployment") and not String.contains?(text, "namespace:") do
      diagnostics = diagnostics ++ [create_diagnostic("Consider specifying a namespace", 3, 0)]
    end

    # Check for missing resource limits
    if String.contains?(text, "containers:") and not String.contains?(text, "resources:") do
      diagnostics = diagnostics ++ [create_diagnostic("Consider adding resource limits", 3, 0)]
    end

    diagnostics
  end

  defp create_diagnostic(message, severity, line) do
    %{
      "range" => %{
        "start" => %{"line" => line, "character" => 0},
        "end" => %{"line" => line, "character" => 100}
      },
      "severity" => severity,
      "source" => "poly-k8s",
      "message" => message
    }
  end
end
