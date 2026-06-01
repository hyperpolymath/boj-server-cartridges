# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyDB.LSP.Handlers.Diagnostics do
  @moduledoc """
  Diagnostics handler for database files.
  """

  require Logger

  def handle(params, assigns) do
    uri = get_in(params, ["textDocument", "uri"]) || ""
    doc = get_in(assigns, [:documents, uri])
    text = if doc, do: doc.text, else: ""

    diagnostics = if String.length(text) == 0 do
      [create_diagnostic("Empty file", 2, 0)]
    else
      []
    end

    %{"uri" => uri, "diagnostics" => diagnostics}
  end

  defp create_diagnostic(message, severity, line) do
    %{
      "range" => %{
        "start" => %{"line" => line, "character" => 0},
        "end" => %{"line" => line, "character" => 100}
      },
      "severity" => severity,
      "source" => "poly-db",
      "message" => message
    }
  end
end
