# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyDB.LSP.Handlers.Completion do
  @moduledoc """
  Auto-completion handler for database configuration and query files.
  """

  def handle(params, assigns) do
    uri = get_in(params, ["textDocument", "uri"])
    position = params["position"]

    doc = get_in(assigns, [:documents, uri])
    text = if doc, do: doc.text, else: ""

    context = get_line_context(text, position["line"], position["character"])
    complete_database(context)
  end

  defp get_line_context(text, line, character) do
    lines = String.split(text, "\n")
    current_line = Enum.at(lines, line, "")
    before_cursor = String.slice(current_line, 0, character)

    %{line: current_line, before_cursor: before_cursor}
  end

  defp complete_database(_context) do
    ["SELECT", "FROM", "WHERE", "INSERT", "UPDATE", "DELETE", "CREATE", "TABLE", "INDEX", "JOIN"]
    |> Enum.map(&create_completion_item(&1, "keyword"))
  end

  defp create_completion_item(label, kind_str) do
    kind = if kind_str == "keyword", do: 14, else: 1

    %{
      "label" => label,
      "kind" => kind,
      "detail" => kind_str,
      "insertText" => label
    }
  end
end
