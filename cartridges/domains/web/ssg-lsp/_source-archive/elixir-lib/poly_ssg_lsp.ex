# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolySSG.LSP do
  @moduledoc """
  Language Server Protocol implementation for 60+ static site generators.

  Provides IDE integration for:
  - Auto-completion (templates, frontmatter, shortcodes)
  - Diagnostics (build errors, configuration issues)
  - Hover documentation (SSG-specific help)
  - Custom commands (build, serve, deploy)

  ## Architecture

  Each SSG adapter runs as an isolated GenServer process under a supervision tree.
  Crashes in one adapter don't affect others. The BEAM VM handles concurrency
  automatically for building multiple SSGs in parallel.

  ## Supported SSGs

  See `PolySSG.Adapters` for the full list of 60+ supported generators.
  """

  @version Mix.Project.config()[:version]

  @doc "Returns the current version"
  def version, do: @version
end
