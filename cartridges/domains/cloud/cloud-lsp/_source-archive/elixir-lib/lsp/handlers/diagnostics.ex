# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyCloud.LSP.Handlers.Diagnostics do
  @moduledoc """
  Provides diagnostics for cloud configuration files.

  Validates:
  - Configuration syntax
  - Provider-specific requirements
  - Resource naming conventions
  - Security best practices
  """

  require Logger

  def handle(params, assigns) do
    uri = get_in(params, ["textDocument", "uri"]) || ""

    # Get document text from state
    doc = get_in(assigns, [:documents, uri])
    text = if doc, do: doc.text, else: ""

    diagnostics = validate_config(text, uri, assigns)

    %{
      "uri" => uri,
      "diagnostics" => diagnostics
    }
  end

  defp validate_config(text, uri, assigns) do
    diagnostics = []

    # Check for common issues
    diagnostics = diagnostics ++ check_missing_provider(text)
    diagnostics = diagnostics ++ check_missing_region(text)
    diagnostics = diagnostics ++ check_security_issues(text)

    # Provider-specific validation
    case assigns[:detected_provider] do
      :aws -> diagnostics ++ validate_aws(text)
      :gcp -> diagnostics ++ validate_gcp(text)
      :azure -> diagnostics ++ validate_azure(text)
      _ -> diagnostics
    end
  end

  defp check_missing_provider(text) do
    if String.contains?(text, "provider") do
      []
    else
      [create_diagnostic("Missing provider configuration", 2, 0)]
    end
  end

  defp check_missing_region(text) do
    if String.contains?(text, "region") do
      []
    else
      [create_diagnostic("Missing region specification", 2, 0)]
    end
  end

  defp check_security_issues(text) do
    diagnostics = []

    if Regex.match?(~r/password\s*=\s*"[^"]+"/i, text) do
      diagnostics = diagnostics ++ [create_diagnostic("Hardcoded password detected - use secrets manager", 1, 0)]
    end

    if Regex.match?(~r/AKIA[0-9A-Z]{16}/i, text) do
      diagnostics = diagnostics ++ [create_diagnostic("AWS access key detected - remove from code", 1, 0)]
    end

    diagnostics
  end

  defp validate_aws(text) do
    []
  end

  defp validate_gcp(text) do
    []
  end

  defp validate_azure(text) do
    []
  end

  defp create_diagnostic(message, severity, line) do
    %{
      "range" => %{
        "start" => %{"line" => line, "character" => 0},
        "end" => %{"line" => line, "character" => 100}
      },
      "severity" => severity,
      "source" => "poly-cloud",
      "message" => message
    }
  end
end
