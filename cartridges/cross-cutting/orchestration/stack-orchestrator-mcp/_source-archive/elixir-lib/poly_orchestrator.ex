# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyOrchestrator.LSP.Application do
  @moduledoc """
  Main application supervisor for poly-orchestrator-lsp.

  Supervises:
  - LSP server (GenLSP)
  - LSP client pool (for communicating with 12 LSP servers)
  - Execution registry (tracks active orchestrations)
  - VeriSimDB connection pool
  """

  use Application

  @impl true
  def start(_type, _args) do
    # Don't start LSP server during tests
    children =
      if Mix.env() == :test do
        [
          # Execution Registry - tracks active orchestrations
          {Registry, keys: :unique, name: PolyOrchestrator.ExecutionRegistry},

          # Dynamic Supervisor for orchestration processes
          {DynamicSupervisor, strategy: :one_for_one, name: PolyOrchestrator.ExecutionSupervisor}
        ]
      else
        [
          # LSP Server
          {PolyOrchestrator.LSP.Server, []},

          # LSP Client Pool - manages connections to 12 LSP servers
          {PolyOrchestrator.Orchestrator.LSPClientPool, []},

          # Execution Registry - tracks active orchestrations
          {Registry, keys: :unique, name: PolyOrchestrator.ExecutionRegistry},

          # Dynamic Supervisor for orchestration processes
          {DynamicSupervisor, strategy: :one_for_one, name: PolyOrchestrator.ExecutionSupervisor}
        ]
      end

    opts = [strategy: :one_for_one, name: PolyOrchestrator.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
