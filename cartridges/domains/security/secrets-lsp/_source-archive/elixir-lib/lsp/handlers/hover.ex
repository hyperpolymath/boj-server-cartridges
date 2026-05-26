# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolySecret.LSP.Handlers.Hover do
  @moduledoc """
  Provides hover documentation for secrets management.

  Shows:
  - Vault command and path documentation
  - SOPS encryption key types
  - Configuration options
  """

  def handle(params, assigns) do
    uri = get_in(params, ["textDocument", "uri"])
    position = params["position"]

    # Get document text from state
    doc = get_in(assigns, [:documents, uri])
    text = if doc, do: doc.text, else: ""

    # Get word at cursor position
    word = get_word_at_position(text, position["line"], position["character"])

    if word do
      # Get documentation based on secret manager and word
      docs = case assigns.detected_secret_manager do
        :vault -> get_vault_docs(word)
        :sops -> get_sops_docs(word)
        _ -> get_generic_docs(word)
      end

      if docs do
        %{
          "contents" => %{
            "kind" => "markdown",
            "value" => docs
          }
        }
      else
        nil
      end
    else
      nil
    end
  end

  # Extract word at position
  defp get_word_at_position(text, line, character) do
    lines = String.split(text, "\n")
    current_line = Enum.at(lines, line, "")

    # Find word boundaries (including underscores)
    before = String.slice(current_line, 0, character) |> String.reverse()
    after_text = String.slice(current_line, character, String.length(current_line))

    start = Regex.run(~r/^[a-zA-Z0-9_]*/, before) |> List.first() |> String.reverse()
    end_part = Regex.run(~r/^[a-zA-Z0-9_]*/, after_text) |> List.first()

    word = start <> end_part
    if String.length(word) > 0, do: word, else: nil
  end

  # Vault documentation
  defp get_vault_docs(word) do
    docs = %{
      "read" => "**vault read** - Read secrets from Vault\n\nReads data from Vault at the given path.\n\nExample: `vault read secret/data/myapp`",
      "write" => "**vault write** - Write secrets to Vault\n\nWrites data to Vault at the given path.\n\nExample: `vault write secret/data/myapp password=secret123`",
      "delete" => "**vault delete** - Delete secrets from Vault\n\nDeletes data at the given path.\n\nExample: `vault delete secret/data/myapp`",
      "list" => "**vault list** - List secrets in Vault\n\nLists keys at the given path.\n\nExample: `vault list secret/metadata`",
      "policy" => "**vault policy** - Manage Vault policies\n\nCommands: write, read, list, delete\n\nExample: `vault policy write myapp policy.hcl`",
      "token" => "**vault token** - Manage tokens\n\nCommands: create, lookup, renew, revoke",
      "auth" => "**vault auth** - Manage authentication methods\n\nCommands: enable, disable, list",
      "secrets" => "**vault secrets** - Manage secrets engines\n\nCommands: enable, disable, list, move, tune",
      "storage" => "**storage** - Backend storage configuration\n\nBackends: file, consul, raft, dynamodb, s3",
      "listener" => "**listener** - API listener configuration\n\nDefines address, port, and TLS settings for Vault API.",
      "seal" => "**seal** - Auto-unseal configuration\n\nTypes: awskms, azurekeyvault, gcpckms, transit",
      "api_addr" => "**api_addr** - Advertised API address\n\nFull URL that clients use to talk to Vault.",
      "cluster_addr" => "**cluster_addr** - Cluster address\n\nAddress for cluster communication.",
      "ui" => "**ui** - Enable/disable web UI\n\nSet to true to enable Vault web interface."
    }

    Map.get(docs, word)
  end

  # SOPS documentation
  defp get_sops_docs(word) do
    docs = %{
      "encrypt" => "**sops encrypt** - Encrypt file\n\nEncrypts a file using configured keys.\n\nExample: `sops encrypt file.yaml`",
      "decrypt" => "**sops decrypt** - Decrypt file\n\nDecrypts an encrypted file.\n\nExample: `sops decrypt file.enc.yaml`",
      "edit" => "**sops edit** - Edit encrypted file\n\nDecrypts, opens editor, and re-encrypts.\n\nExample: `sops edit secrets.yaml`",
      "rotate" => "**sops rotate** - Rotate encryption keys\n\nRe-encrypts file with new key generation.\n\nExample: `sops rotate -i file.yaml`",
      "updatekeys" => "**sops updatekeys** - Update encryption keys\n\nUpdates keys based on .sops.yaml rules.\n\nExample: `sops updatekeys file.yaml`",
      "creation_rules" => "**creation_rules** - Encryption rules\n\nDefines which keys to use for encryption based on path patterns.",
      "path_regex" => "**path_regex** - Path matching pattern\n\nRegular expression to match file paths.",
      "encrypted_regex" => "**encrypted_regex** - Field encryption pattern\n\nRegex to match which fields to encrypt in files.",
      "kms" => "**kms** - AWS KMS key ARN\n\nAWS KMS key for encryption.\n\nFormat: `arn:aws:kms:region:account:key/id`",
      "aws_kms" => "**aws_kms** - AWS KMS encryption\n\nUses AWS Key Management Service for encryption.",
      "gcp_kms" => "**gcp_kms** - Google Cloud KMS\n\nUses GCP Key Management Service for encryption.",
      "azure_kv" => "**azure_kv** - Azure Key Vault\n\nUses Azure Key Vault for encryption.",
      "age" => "**age** - Age encryption\n\nModern encryption tool with simple keys.",
      "pgp" => "**pgp** - PGP/GPG encryption\n\nUses PGP public keys for encryption.",
      "shamir_threshold" => "**shamir_threshold** - Shamir secret sharing\n\nMinimum number of keys required to decrypt (M of N).",
      "key_groups" => "**key_groups** - Key group definitions\n\nGroups of keys for multi-key encryption."
    }

    Map.get(docs, word)
  end

  # Generic secret management documentation
  defp get_generic_docs(word) do
    docs = %{
      "encrypt" => "**encrypt** - Encrypt sensitive data\n\nEncrypts data using configured encryption method.",
      "decrypt" => "**decrypt** - Decrypt encrypted data\n\nDecrypts data using available keys.",
      "rotate" => "**rotate** - Rotate encryption keys\n\nChanges encryption keys and re-encrypts data.",
      "read" => "**read** - Read secret value\n\nRetrieves secret from secrets management system.",
      "write" => "**write** - Write secret value\n\nStores secret in secrets management system."
    }

    Map.get(docs, word)
  end
end
