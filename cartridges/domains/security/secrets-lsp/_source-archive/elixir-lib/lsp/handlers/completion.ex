# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolySecret.LSP.Handlers.Completion do
  @moduledoc """
  Provides auto-completion for secrets management.

  Supports:
  - HashiCorp Vault paths and operations
  - SOPS encryption keys and rules
  - Secret path patterns
  """

  def handle(params, assigns) do
    uri = get_in(params, ["textDocument", "uri"])
    position = params["position"]

    # Get document text from state
    doc = get_in(assigns, [:documents, uri])
    text = if doc, do: doc.text, else: ""

    # Get line and character position
    line = position["line"]
    character = position["character"]

    # Get context around cursor
    context = get_line_context(text, line, character)

    # Provide completions based on context and detected secret manager
    completions = case assigns.detected_secret_manager do
      :vault -> complete_vault(context, uri)
      :sops -> complete_sops(context, uri)
      _ -> complete_generic(context)
    end

    completions
  end

  # Extract line context around cursor
  defp get_line_context(text, line, character) do
    lines = String.split(text, "\n")
    current_line = Enum.at(lines, line, "")
    before_cursor = String.slice(current_line, 0, character)

    %{
      line: current_line,
      before_cursor: before_cursor,
      trigger: get_trigger(before_cursor)
    }
  end

  # Detect completion trigger
  defp get_trigger(text) do
    cond do
      String.match?(text, ~r/vault\s+\w*$/) -> :vault_command
      String.match?(text, ~r/path\s*=\s*"[^"]*$/) -> :vault_path
      String.match?(text, ~r/sops\s+\w*$/) -> :sops_command
      String.match?(text, ~r/kms\s*:\s*$/) -> :sops_key_type
      String.ends_with?(text, "/") -> :path_segment
      true -> :none
    end
  end

  # Vault completions
  defp complete_vault(context, uri) do
    case context.trigger do
      :vault_command ->
        ["read", "write", "delete", "list", "policy", "token", "auth", "secrets"]
        |> Enum.map(&create_completion_item(&1, "function"))

      :vault_path ->
        [
          "secret/data/", "secret/metadata/",
          "kv/data/", "kv/metadata/",
          "database/creds/", "pki/issue/",
          "auth/token/", "sys/policy/"
        ]
        |> Enum.map(&create_completion_item(&1, "value"))

      :path_segment ->
        if String.contains?(uri, "vault") do
          ["api-keys", "database", "certificates", "tokens", "config"]
          |> Enum.map(&create_completion_item(&1, "value"))
        else
          []
        end

      _ ->
        # Vault configuration keys
        if String.ends_with?(uri, ".hcl") do
          ["storage", "listener", "seal", "api_addr", "cluster_addr", "ui"]
          |> Enum.map(&create_completion_item(&1, "field"))
        else
          []
        end
    end
  end

  # SOPS completions
  defp complete_sops(context, uri) do
    case context.trigger do
      :sops_command ->
        ["encrypt", "decrypt", "edit", "rotate", "publish", "updatekeys"]
        |> Enum.map(&create_completion_item(&1, "function"))

      :sops_key_type ->
        ["aws_kms", "gcp_kms", "azure_kv", "age", "pgp"]
        |> Enum.map(&create_completion_item(&1, "enum"))

      _ ->
        if String.ends_with?(uri, ".sops.yaml") or String.ends_with?(uri, ".sops.yml") do
          # SOPS config fields
          [
            "creation_rules", "path_regex", "encrypted_regex",
            "kms", "gcp_kms", "azure_kv", "age", "pgp",
            "shamir_threshold", "key_groups"
          ]
          |> Enum.map(&create_completion_item(&1, "field"))
        else
          []
        end
    end
  end

  # Generic secret manager completions
  defp complete_generic(context) do
    case context.trigger do
      :none ->
        ["encrypt", "decrypt", "rotate", "read", "write"]
        |> Enum.map(&create_completion_item(&1, "function"))

      _ ->
        []
    end
  end

  # Create LSP completion item
  defp create_completion_item(label, kind_str) do
    kind = case kind_str do
      "function" -> 3    # Function
      "field" -> 5       # Field
      "value" -> 12      # Value
      "enum" -> 13       # Enum
      _ -> 1             # Text
    end

    %{
      "label" => label,
      "kind" => kind,
      "detail" => "#{kind_str}",
      "insertText" => label
    }
  end
end
