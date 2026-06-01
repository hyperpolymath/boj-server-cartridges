# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyGit.LSP.Handlers.Diagnostics do
  @moduledoc """
  Diagnostics handler for Git files.
  """

  require Logger

  def handle(params, assigns) do
    uri = get_in(params, ["textDocument", "uri"]) || ""
    doc = get_in(assigns, [:documents, uri])
    text = if doc, do: doc.text, else: ""

    diagnostics = validate_commit_message(text)

    %{"uri" => uri, "diagnostics" => diagnostics}
  end

  defp validate_commit_message(text) do
    diagnostics = []

    lines = String.split(text, "\n")
    first_line = List.first(lines) || ""

    if String.length(first_line) > 72 do
      diagnostics = diagnostics ++ [create_diagnostic("Commit subject line too long (> 72 chars)", 2, 0)]
    end

    diagnostics
  end

  defp create_diagnostic(message, severity, line) do
    %{
      "range" => %{
        "start" => %{"line" => line, "character" => 0},
        "end" => %{"line" => line, "character" => 100}
      },
      "severity" => severity,
      "source" => "poly-git",
      "message" => message
    }
  end
end
