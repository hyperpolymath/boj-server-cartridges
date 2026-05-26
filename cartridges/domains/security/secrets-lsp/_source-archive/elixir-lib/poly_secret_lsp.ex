# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolySecret.LSP do
  @moduledoc """
  Language Server Protocol implementation for secrets management.

  Provides IDE integration for:
  - Auto-completion (secret paths, fields)
  - Diagnostics (missing secrets, validation errors)
  - Hover documentation (secret metadata)
  - Custom commands (read, write, rotate keys)

  ## Supported Backends

  - **HashiCorp Vault**: Enterprise secrets management with versioning
  - **Mozilla SOPS**: File-based encryption with multiple backends

  ## Security Architecture

  All secrets operations are:
  - Authenticated via backend-specific credentials
  - Never logged in plaintext
  - Audited at the adapter level
  - Isolated in separate BEAM processes for fault tolerance

  ## Architecture

  Each secrets backend adapter runs as an isolated GenServer process under
  a supervision tree. Crashes in one adapter don't affect others. The BEAM
  VM handles concurrency automatically for parallel operations.
  """

  @version Mix.Project.config()[:version]

  @doc "Returns the current version"
  def version, do: @version
end
