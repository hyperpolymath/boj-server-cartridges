# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolySecret.LSP.Handlers.Diagnostics do
  @moduledoc """
  Provides diagnostics for secrets management.

  Validates:
  - Vault configuration and policies
  - SOPS encryption rules
  - Secret file formats
  - Encryption status
  """

  require Logger

  @doc """
  Handle diagnostics request by running validation and parsing output.

  Returns LSP diagnostics format.
  """
  def handle(params, %{project_path: project_path, detected_secret_manager: manager}) when project_path != nil do
    uri = get_in(params, ["textDocument", "uri"]) || "file://#{project_path}"

    diagnostics =
      case run_validation(uri, project_path, manager) do
        {:ok, _output} ->
          # Validation succeeded - no diagnostics
          []

        {:error, error_output} ->
          # Parse errors from validation output
          parse_errors(error_output, manager)
      end

    %{
      "uri" => uri,
      "diagnostics" => diagnostics
    }
  end

  def handle(_params, _assigns) do
    # No project path - return empty diagnostics
    %{"uri" => "", "diagnostics" => []}
  end

  # Run validation based on secret manager
  defp run_validation(uri, project_path, :vault) do
    cond do
      String.ends_with?(uri, ".hcl") ->
        validate_vault_config(uri)

      String.contains?(uri, "policy") and String.ends_with?(uri, ".hcl") ->
        validate_vault_policy(uri)

      true ->
        {:ok, "No specific Vault file to validate"}
    end
  end

  defp run_validation(uri, project_path, :sops) do
    cond do
      String.ends_with?(uri, ".sops.yaml") or String.ends_with?(uri, ".sops.yml") ->
        validate_sops_config(uri)

      String.contains?(uri, ".enc.") or String.contains?(uri, "secrets") ->
        validate_sops_encryption(uri)

      true ->
        {:ok, "No specific SOPS file to validate"}
    end
  end

  defp run_validation(_uri, _project_path, _manager) do
    {:ok, "No validation available"}
  end

  # Validate Vault configuration
  defp validate_vault_config(uri) do
    file_path = URI.parse(uri).path

    case File.read(file_path) do
      {:ok, content} ->
        # Basic HCL syntax validation
        if String.contains?(content, "storage") and String.contains?(content, "listener") do
          {:ok, "Valid Vault config"}
        else
          {:error, "WARNING: Missing required sections (storage or listener)"}
        end

      {:error, reason} ->
        {:error, "Cannot read file: #{inspect(reason)}"}
    end
  end

  # Validate Vault policy
  defp validate_vault_policy(uri) do
    file_path = URI.parse(uri).path

    case System.cmd("vault", ["policy", "fmt", file_path], stderr_to_stdout: true) do
      {_output, 0} -> {:ok, "Valid policy"}
      {error, _} -> {:error, error}
    end
  rescue
    e -> {:error, "vault CLI not found: #{inspect(e)}"}
  end

  # Validate SOPS configuration
  defp validate_sops_config(uri) do
    file_path = URI.parse(uri).path

    case File.read(file_path) do
      {:ok, content} ->
        case YamlElixir.read_from_string(content) do
          {:ok, config} ->
            if Map.has_key?(config, "creation_rules") do
              {:ok, "Valid SOPS config"}
            else
              {:error, "WARNING: Missing creation_rules"}
            end

          {:error, error} ->
            {:error, "YAML parse error: #{inspect(error)}"}
        end

      {:error, reason} ->
        {:error, "Cannot read file: #{inspect(reason)}"}
    end
  rescue
    e -> {:error, "YAML validation failed: #{inspect(e)}"}
  end

  # Validate SOPS encryption status
  defp validate_sops_encryption(uri) do
    file_path = URI.parse(uri).path

    case File.read(file_path) do
      {:ok, content} ->
        # Check if file is encrypted (contains sops metadata)
        if String.contains?(content, "sops:") and String.contains?(content, "mac:") do
          {:ok, "File is encrypted"}
        else
          {:error, "WARNING: File appears unencrypted but is in secrets directory"}
        end

      {:error, reason} ->
        {:error, "Cannot read file: #{inspect(reason)}"}
    end
  end

  # Parse error messages from validation output
  defp parse_errors(output, _manager) do
    output
    |> String.split("\n")
    |> Enum.flat_map(&parse_error_line(&1))
    |> Enum.take(50)  # Limit to 50 diagnostics
  end

  # Parse error lines
  defp parse_error_line("ERROR: " <> message) do
    [create_diagnostic(message, 1)]
  end

  defp parse_error_line("WARNING: " <> message) do
    [create_diagnostic(message, 2)]
  end

  defp parse_error_line(line) do
    cond do
      String.contains?(line, "error:") or String.contains?(line, "Error") ->
        [create_diagnostic(line, 1)]

      String.contains?(line, "warning:") or String.contains?(line, "Warning") ->
        [create_diagnostic(line, 2)]

      true ->
        []
    end
  end

  # Create a diagnostic entry
  defp create_diagnostic(message, severity) do
    %{
      "range" => %{
        "start" => %{"line" => 0, "character" => 0},
        "end" => %{"line" => 0, "character" => 100}
      },
      "severity" => severity,
      "source" => "poly-secret",
      "message" => String.trim(message)
    }
  end
end
