# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyGit.LSP.Handlers.Completion do
  @moduledoc """
  Auto-completion handler for Git files (commit messages, config).
  """

  def handle(params, assigns) do
    uri = get_in(params, ["textDocument", "uri"])
    position = params["position"]

    doc = get_in(assigns, [:documents, uri])
    text = if doc, do: doc.text, else: ""

    context = get_line_context(text, position["line"], position["character"])
    complete_git(context)
  end

  defp get_line_context(text, line, character) do
    lines = String.split(text, "\n")
    current_line = Enum.at(lines, line, "")
    before_cursor = String.slice(current_line, 0, character)

    %{line: current_line, before_cursor: before_cursor}
  end

  defp complete_git(_context) do
    ["feat", "fix", "docs", "style", "refactor", "test", "chore", "Closes", "Refs", "Breaking"]
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
