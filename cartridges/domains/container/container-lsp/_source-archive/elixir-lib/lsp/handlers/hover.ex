# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyContainer.LSP.Handlers.Hover do
  @moduledoc """
  Hover documentation handler for container files.
  """

  def handle(params, assigns) do
    uri = get_in(params, ["textDocument", "uri"])
    position = params["position"]

    doc = get_in(assigns, [:documents, uri])
    text = if doc, do: doc.text, else: ""

    word = get_word_at_position(text, position["line"], position["character"])

    if word do
      docs = get_container_docs(word)
      if docs, do: %{"contents" => %{"kind" => "markdown", "value" => docs}}, else: nil
    else
      nil
    end
  end

  defp get_word_at_position(text, line, character) do
    lines = String.split(text, "\n")
    current_line = Enum.at(lines, line, "")

    before = String.slice(current_line, 0, character) |> String.reverse()
    after_text = String.slice(current_line, character, String.length(current_line))

    start = Regex.run(~r/^[a-zA-Z0-9_-]*/, before) |> List.first() |> String.reverse()
    end_part = Regex.run(~r/^[a-zA-Z0-9_-]*/, after_text) |> List.first()

    word = start <> end_part
    if String.length(word) > 0, do: word, else: nil
  end

  defp get_container_docs(word) do
    docs = %{
      "FROM" => "**FROM** - Set the base image for subsequent instructions",
      "RUN" => "**RUN** - Execute commands in a new layer",
      "COPY" => "**COPY** - Copy files or directories",
      "WORKDIR" => "**WORKDIR** - Set the working directory",
      "EXPOSE" => "**EXPOSE** - Inform Docker that the container listens on the specified network ports"
    }
    Map.get(docs, word)
  end
end
