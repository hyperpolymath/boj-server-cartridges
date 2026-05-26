# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolySecret.Adapters.SOPS do
  @moduledoc """
  Mozilla SOPS adapter for secrets management.

  Uses the `sops` CLI to interact with SOPS-encrypted files. Requires:
  - `sops` binary in PATH
  - GPG, age, or AWS KMS configured for encryption

  SOPS supports multiple file formats:
  - YAML (recommended for configuration)
  - JSON
  - ENV
  - INI

  ## Security Notes

  - SOPS encrypts only values, not keys (allows diffs)
  - Supports multiple encryption backends (GPG, age, AWS KMS, GCP KMS, Azure Key Vault)
  - Key rotation is done by re-encrypting with new keys
  """

  use GenServer
  @behaviour PolySecret.Adapters.Behaviour

  require Logger

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def detect(project_path) do
    # Check for .sops.yaml config file
    sops_config = Path.join(project_path, ".sops.yaml")
    sops_exists = File.exists?(sops_config)

    # Also check for any *.sops.yaml or *.sops.json files
    has_sops_files =
      project_path
      |> Path.join("**/*.sops.{yaml,yml,json}")
      |> Path.wildcard()
      |> length() > 0

    {:ok, sops_exists || has_sops_files}
  end

  @impl true
  def read_secret(secret_path, opts \\ []) do
    field = Keyword.get(opts, :field)

    args = ["-d", secret_path]

    case run_sops_command(args) do
      {:ok, output} ->
        # Determine format from file extension
        case parse_sops_output(output, secret_path) do
          {:ok, data} ->
            result = if field, do: get_nested_field(data, field), else: data
            {:ok, result}

          {:error, _} = err ->
            err
        end

      {:error, _} = err ->
        err
    end
  end

  @impl true
  def write_secret(secret_path, secret_data, _opts \\ []) do
    # Read existing file if it exists to preserve structure
    existing_data =
      case File.read(secret_path) do
        {:ok, content} -> parse_sops_output(content, secret_path)
        {:error, _} -> {:ok, %{}}
      end

    case existing_data do
      {:ok, current_data} ->
        # Merge new data with existing
        merged_data = Map.merge(current_data, secret_data)

        # Write to temp file, then encrypt
        temp_file = "#{secret_path}.tmp"

        format = get_format_from_path(secret_path)
        serialized = serialize_data(merged_data, format)

        case File.write(temp_file, serialized) do
          :ok ->
            args = ["-e", "-i", temp_file]

            case run_sops_command(args) do
              {:ok, _} ->
                # Move temp file to target
                case File.rename(temp_file, secret_path) do
                  :ok -> {:ok, :written}
                  {:error, reason} -> {:error, "Failed to move file: #{reason}"}
                end

              {:error, _} = err ->
                File.rm(temp_file)
                err
            end

          {:error, reason} ->
            {:error, "Failed to write temp file: #{reason}"}
        end

      {:error, _} = err ->
        err
    end
  end

  @impl true
  def list_secrets(secret_path, opts \\ []) do
    recursive = Keyword.get(opts, :recursive, false)

    pattern =
      if recursive do
        Path.join(secret_path, "**/*.sops.{yaml,yml,json,env,ini}")
      else
        Path.join(secret_path, "*.sops.{yaml,yml,json,env,ini}")
      end

    files = Path.wildcard(pattern)
    {:ok, files}
  end

  @impl true
  def delete_secret(secret_path, _opts \\ []) do
    # SOPS doesn't have a delete command, just delete the file
    case File.rm(secret_path) do
      :ok -> {:ok, :deleted}
      {:error, reason} -> {:error, "Failed to delete file: #{reason}"}
    end
  end

  @impl true
  def rotate_key(secret_path, opts \\ []) do
    # SOPS key rotation: decrypt and re-encrypt with new keys
    args =
      case Keyword.get(opts, :add_keys) do
        nil -> ["-r", "-i", secret_path]
        keys -> ["-r", "-i", "--add-pgp", keys, secret_path]
      end

    case run_sops_command(args) do
      {:ok, _output} -> {:ok, :rotated}
      {:error, _} = err -> err
    end
  end

  @impl true
  def version do
    case run_sops_command(["--version"]) do
      {:ok, output} ->
        # Extract version from "sops 3.7.3 (latest)"
        case Regex.run(~r/sops ([\d.]+)/, output) do
          [_, version] -> {:ok, version}
          _ -> {:error, "Could not parse sops version"}
        end

      {:error, _} = err ->
        err
    end
  end

  @impl true
  def metadata do
    %{
      name: "Mozilla SOPS",
      type: "sops",
      description: "Simple and flexible secrets encryption with multiple backend support",
      supports_versioning: false,
      supports_key_rotation: true
    }
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  # Private helpers

  defp run_sops_command(args) do
    case System.find_executable("sops") do
      nil ->
        {:error, "sops CLI not found in PATH"}

      sops_bin ->
        case System.cmd(sops_bin, args, stderr_to_stdout: true) do
          {output, 0} ->
            {:ok, output}

          {error, _code} ->
            Logger.error("SOPS command failed (details omitted for security)")
            {:error, "SOPS operation failed: #{sanitize_error(error)}"}
        end
    end
  end

  defp sanitize_error(error) do
    error
    |> String.split("\n")
    |> Enum.take(1)
    |> Enum.join()
    |> String.slice(0..100)
  end

  defp parse_sops_output(output, path) do
    case get_format_from_path(path) do
      :yaml ->
        YamlElixir.read_from_string(output)

      :json ->
        Jason.decode(output)

      :env ->
        # Parse ENV format (key=value lines)
        lines =
          output
          |> String.split("\n", trim: true)
          |> Enum.reject(&String.starts_with?(&1, "#"))

        data =
          Enum.reduce(lines, %{}, fn line, acc ->
            case String.split(line, "=", parts: 2) do
              [key, value] -> Map.put(acc, key, value)
              _ -> acc
            end
          end)

        {:ok, data}

      _ ->
        {:error, "Unsupported format"}
    end
  end

  defp get_format_from_path(path) do
    cond do
      String.ends_with?(path, [".yaml", ".yml"]) -> :yaml
      String.ends_with?(path, ".json") -> :json
      String.ends_with?(path, ".env") -> :env
      String.ends_with?(path, ".ini") -> :ini
      true -> :yaml
    end
  end

  defp serialize_data(data, format) do
    case format do
      :yaml ->
        Ymlr.document!(data)

      :json ->
        Jason.encode!(data, pretty: true)

      :env ->
        Enum.map_join(data, "\n", fn {k, v} -> "#{k}=#{v}" end)

      _ ->
        Ymlr.document!(data)
    end
  end

  defp get_nested_field(data, field) when is_map(data) do
    # Support nested field access like "database.password"
    keys = String.split(field, ".")
    Enum.reduce(keys, data, fn key, acc -> Map.get(acc, key) end)
  end

  defp get_nested_field(_data, _field), do: nil
end
