# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyObservability.LSP do
  @moduledoc """
  Language Server Protocol implementation for observability tools.

  Provides IDE integration for Prometheus, Grafana, Loki, and Jaeger.
  """

  @doc """
  Returns the version of the LSP server.
  """
  def version, do: "0.1.0"
end
