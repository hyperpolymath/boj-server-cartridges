# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyProof.LSP do
  @moduledoc """
  Language Server Protocol implementation for proof assistants.

  Provides IDE integration for:
  - Proof checking and validation
  - Goal display and navigation
  - Tactic auto-completion
  - Theorem search
  - Hover documentation (proof state, types)
  - Custom commands (check proof, show goals, apply tactic)

  ## Architecture

  Each proof assistant adapter runs as an isolated GenServer process under a supervision tree.
  Crashes in one adapter don't affect others. The BEAM VM handles concurrency
  automatically for checking multiple proofs in parallel.

  ## Supported Proof Assistants

  - Coq (coqc, coqtop)
  - Lean (lean)
  - Isabelle (isabelle)
  - Agda (agda)
  """

  @version Mix.Project.config()[:version]

  @doc "Returns the current version"
  def version, do: @version
end
