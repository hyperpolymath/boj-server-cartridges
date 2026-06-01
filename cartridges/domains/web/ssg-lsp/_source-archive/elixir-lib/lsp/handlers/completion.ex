# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolySSG.LSP.Handlers.Completion do
  @moduledoc """
  Provides auto-completion for SSG templates and configuration.

  Supports:
  - Template syntax (Tera, Liquid, Jinja)
  - Frontmatter fields
  - Shortcodes
  - Configuration keys
  """

  def handle(params, assigns) do
    uri = get_in(params, ["textDocument", "uri"])
    position = params["position"]

    # Get document text from state
    doc = get_in(assigns, [:documents, uri])
    text = if doc, do: doc.text, else: ""

    # Get line and character position
    line = position["line"]
    character = position["character"]

    # Get context around cursor
    context = get_line_context(text, line, character)

    # Provide completions based on context and detected SSG
    completions = case assigns.detected_ssg do
      :zola -> complete_zola(context)
      :hakyll -> complete_hakyll(context)
      :franklin -> complete_franklin(context)
      _ -> complete_generic(context)
    end

    completions
  end

  # Extract line context around cursor
  defp get_line_context(text, line, character) do
    lines = String.split(text, "\n")
    current_line = Enum.at(lines, line, "")
    before_cursor = String.slice(current_line, 0, character)

    %{
      line: current_line,
      before_cursor: before_cursor,
      trigger: get_trigger(before_cursor)
    }
  end

  # Detect completion trigger ({{, {%, @, etc.)
  defp get_trigger(text) do
    cond do
      String.ends_with?(text, "{{") -> :template_var
      String.ends_with?(text, "{%") -> :template_tag
      String.ends_with?(text, "@") -> :frontmatter
      String.ends_with?(text, "#") -> :markdown_header
      true -> :none
    end
  end

  # Zola (Tera templates) completions
  defp complete_zola(context) do
    case context.trigger do
      :template_var ->
        ["page", "section", "config", "page.title", "page.content", "page.date", "page.permalink"]
        |> Enum.map(&create_completion_item(&1, "variable"))

      :template_tag ->
        ["if", "for", "block", "extends", "include", "macro", "set"]
        |> Enum.map(&create_completion_item(&1, "keyword"))

      :frontmatter ->
        ["title", "date", "description", "template", "taxonomies", "extra"]
        |> Enum.map(&create_completion_item(&1, "field"))

      _ ->
        []
    end
  end

  # Hakyll completions
  defp complete_hakyll(context) do
    case context.trigger do
      :template_var ->
        ["$title$", "$body$", "$url$", "$date$", "$author$"]
        |> Enum.map(&create_completion_item(&1, "variable"))

      :frontmatter ->
        ["title", "date", "author", "tags"]
        |> Enum.map(&create_completion_item(&1, "field"))

      _ ->
        []
    end
  end

  # Franklin.jl completions
  defp complete_franklin(context) do
    case context.trigger do
      :frontmatter ->
        ["@def title", "@def author", "@def published", "@def tags"]
        |> Enum.map(&create_completion_item(&1, "field"))

      _ ->
        []
    end
  end

  # Generic SSG completions
  defp complete_generic(context) do
    case context.trigger do
      :frontmatter ->
        ["title", "date", "author", "description", "tags"]
        |> Enum.map(&create_completion_item(&1, "field"))

      _ ->
        []
    end
  end

  # Create LSP completion item
  defp create_completion_item(label, kind_str) do
    kind = case kind_str do
      "variable" -> 6   # Variable
      "keyword" -> 14   # Keyword
      "field" -> 5      # Field
      _ -> 1            # Text
    end

    %{
      "label" => label,
      "kind" => kind,
      "detail" => "#{kind_str}",
      "insertText" => label
    }
  end
end
