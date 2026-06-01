# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolySecret.Adapters.Vault do
  @moduledoc """
  HashiCorp Vault adapter for secrets management.

  Uses the `vault` CLI to interact with Vault. Requires:
  - `vault` binary in PATH
  - VAULT_ADDR environment variable set
  - VAULT_TOKEN environment variable set or .vault-token file

  ## Security Notes

  - All vault operations are authenticated via VAULT_TOKEN
  - Secrets are never logged in plaintext
  - Supports Vault's KV v2 secrets engine with versioning
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
    # Check for .vault-token file or VAULT_TOKEN env var
    vault_token_file = Path.join(project_path, ".vault-token")
    vault_token_exists = File.exists?(vault_token_file) || System.get_env("VAULT_TOKEN") != nil
    vault_addr_exists = System.get_env("VAULT_ADDR") != nil

    {:ok, vault_token_exists && vault_addr_exists}
  end

  @impl true
  def read_secret(secret_path, opts \\ []) do
    version = Keyword.get(opts, :version)
    field = Keyword.get(opts, :field)

    args =
      case version do
        nil -> ["kv", "get", "-format=json", secret_path]
        v -> ["kv", "get", "-format=json", "-version=#{v}", secret_path]
      end

    case run_vault_command(args) do
      {:ok, output} ->
        case Jason.decode(output) do
          {:ok, %{"data" => %{"data" => data}}} ->
            result = if field, do: Map.get(data, field), else: data
            {:ok, result}

          {:error, _} = err ->
            err
        end

      {:error, _} = err ->
        err
    end
  end

  @impl true
  def write_secret(secret_path, secret_data, opts \\ []) do
    cas = Keyword.get(opts, :cas)

    # Convert secret_data map to key=value arguments
    data_args =
      Enum.flat_map(secret_data, fn {k, v} ->
        ["#{k}=#{v}"]
      end)

    args =
      case cas do
        nil -> ["kv", "put", secret_path | data_args]
        version -> ["kv", "put", "-cas=#{version}", secret_path | data_args]
      end

    case run_vault_command(args) do
      {:ok, _output} -> {:ok, :written}
      {:error, _} = err -> err
    end
  end

  @impl true
  def list_secrets(secret_path, opts \\ []) do
    recursive = Keyword.get(opts, :recursive, false)

    args =
      if recursive do
        ["kv", "list", "-format=json", secret_path]
      else
        ["kv", "list", "-format=json", secret_path]
      end

    case run_vault_command(args) do
      {:ok, output} ->
        case Jason.decode(output) do
          {:ok, list} when is_list(list) -> {:ok, list}
          {:ok, _} -> {:ok, []}
          {:error, _} = err -> err
        end

      {:error, _} = err ->
        err
    end
  end

  @impl true
  def delete_secret(secret_path, opts \\ []) do
    versions = Keyword.get(opts, :versions)
    destroy = Keyword.get(opts, :destroy, false)

    args =
      cond do
        destroy && versions ->
          ["kv", "destroy", "-versions=#{Enum.join(versions, ",")}", secret_path]

        destroy ->
          ["kv", "metadata", "delete", secret_path]

        versions ->
          ["kv", "delete", "-versions=#{Enum.join(versions, ",")}", secret_path]

        true ->
          ["kv", "delete", secret_path]
      end

    case run_vault_command(args) do
      {:ok, _output} -> {:ok, :deleted}
      {:error, _} = err -> err
    end
  end

  @impl true
  def rotate_key(_secret_path, _opts \\ []) do
    # Vault doesn't support per-secret key rotation via CLI
    # This would typically be handled at the encryption key level
    {:error, "Key rotation not supported via vault CLI"}
  end

  @impl true
  def version do
    case run_vault_command(["version"]) do
      {:ok, output} ->
        # Extract version from "Vault v1.15.0 (deadbeef)"
        case Regex.run(~r/Vault v([\d.]+)/, output) do
          [_, version] -> {:ok, version}
          _ -> {:error, "Could not parse vault version"}
        end

      {:error, _} = err ->
        err
    end
  end

  @impl true
  def metadata do
    %{
      name: "HashiCorp Vault",
      type: "vault",
      description: "Enterprise secrets management with versioning and access control",
      supports_versioning: true,
      supports_key_rotation: false
    }
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  # Private helpers

  defp run_vault_command(args) do
    case System.find_executable("vault") do
      nil ->
        {:error, "vault CLI not found in PATH"}

      vault_bin ->
        case System.cmd(vault_bin, args, stderr_to_stdout: true) do
          {output, 0} ->
            {:ok, output}

          {error, _code} ->
            # Never log the full error as it might contain secrets
            Logger.error("Vault command failed (details omitted for security)")
            {:error, "Vault operation failed: #{sanitize_error(error)}"}
        end
    end
  end

  defp sanitize_error(error) do
    # Remove any potential secret values from error messages
    error
    |> String.split("\n")
    |> Enum.take(1)
    |> Enum.join()
    |> String.slice(0..100)
  end
end
