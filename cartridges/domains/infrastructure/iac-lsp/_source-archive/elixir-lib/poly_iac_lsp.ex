# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyIaC.LSP do
  @moduledoc """
  Language Server Protocol implementation for Infrastructure as Code tools.

  Provides IDE integration for:
  - Auto-completion (HCL syntax, resource types, attributes)
  - Diagnostics (validation errors, plan output)
  - Hover documentation (resource documentation)
  - Custom commands (init, plan, apply, destroy)

  ## Architecture

  Each IaC tool adapter runs as an isolated GenServer process under a supervision tree.
  Crashes in one adapter don't affect others. The BEAM VM handles concurrency
  automatically for managing multiple IaC projects in parallel.

  ## Supported Tools

  - OpenTofu (FOSS-first, preferred over Terraform)
  - Pulumi (multi-language IaC)

  ## FOSS-First Policy

  Per hyperpolymath development standards, we prefer FOSS tools:
  - OpenTofu over Terraform (MPL-2.0 vs BSL)
  - Self-hosted Pulumi backends over Pulumi Cloud
  """

  @version Mix.Project.config()[:version]

  @doc "Returns the current version"
  def version, do: @version
end
