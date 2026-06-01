# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolySecret.Adapters.Behaviour do
  @moduledoc """
  Behaviour defining the contract for secrets management adapters.

  Each adapter implements this behaviour to provide a consistent interface
  for detecting, reading, writing, and managing secrets across different
  secret management backends (HashiCorp Vault, Mozilla SOPS, etc.).

  ## Security Considerations

  - All secret operations must be audited
  - Secrets should never be logged in plaintext
  - Adapters must validate authentication before operations
  - Key rotation must be atomic to prevent inconsistent state

  ## Example

      defmodule PolySecret.Adapters.Vault do
        use GenServer
        @behaviour PolySecret.Adapters.Behaviour

        @impl true
        def detect(project_path) do
          vault_config_exists = File.exists?(Path.join(project_path, ".vault-token"))
          {:ok, vault_config_exists}
        end

        @impl true
        def read_secret(path, opts) do
          # Use vault CLI to read secret
        end
      end
  """

  @type project_path :: String.t()
  @type secret_path :: String.t()
  @type secret_data :: map()
  @type opts :: keyword()
  @type result :: {:ok, term()} | {:error, String.t()}
  @type detect_result :: {:ok, boolean()} | {:error, String.t()}

  @doc """
  Detect if this secrets backend is configured in the project directory.

  Returns `{:ok, true}` if the backend's config exists, `{:ok, false}` otherwise.
  """
  @callback detect(project_path) :: detect_result

  @doc """
  Read a secret from the backend.

  ## Options

  - `:version` - Read a specific version (if backend supports versioning)
  - `:field` - Read a specific field from the secret
  """
  @callback read_secret(secret_path, opts) :: {:ok, secret_data} | {:error, String.t()}

  @doc """
  Write a secret to the backend.

  ## Options

  - `:cas` - Check-and-Set version (for atomic updates)
  - `:metadata` - Additional metadata to store with the secret
  """
  @callback write_secret(secret_path, secret_data, opts) :: result

  @doc """
  List all secrets at a path (non-recursive by default).

  ## Options

  - `:recursive` - List secrets recursively
  """
  @callback list_secrets(secret_path, opts) :: {:ok, [String.t()]} | {:error, String.t()}

  @doc """
  Delete a secret from the backend.

  ## Options

  - `:versions` - Specific versions to delete (if backend supports versioning)
  - `:destroy` - Permanently destroy vs soft delete
  """
  @callback delete_secret(secret_path, opts) :: result

  @doc """
  Rotate encryption key for a secret.

  This re-encrypts the secret with a new key without changing the plaintext value.
  """
  @callback rotate_key(secret_path, opts) :: result

  @doc """
  Get backend version.
  """
  @callback version() :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Get backend metadata (name, type, description).
  """
  @callback metadata() :: %{
              name: String.t(),
              type: String.t(),
              description: String.t(),
              supports_versioning: boolean(),
              supports_key_rotation: boolean()
            }
end
