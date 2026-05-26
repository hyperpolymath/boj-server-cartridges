# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolySSG.LSP.Handlers.Hover do
  @moduledoc """
  Provides hover documentation for SSG-specific syntax.

  Shows:
  - Template function documentation
  - Shortcode usage examples
  - Configuration option descriptions
  """

  def handle(params, assigns) do
    uri = get_in(params, ["textDocument", "uri"])
    position = params["position"]

    # Get document text from state
    doc = get_in(assigns, [:documents, uri])
    text = if doc, do: doc.text, else: ""

    # Get word at cursor position
    word = get_word_at_position(text, position["line"], position["character"])

    if word do
      # Get documentation based on SSG type and word
      docs = case assigns.detected_ssg do
        :zola -> get_zola_docs(word)
        :hakyll -> get_hakyll_docs(word)
        :franklin -> get_franklin_docs(word)
        _ -> get_generic_docs(word)
      end

      if docs do
        %{
          "contents" => %{
            "kind" => "markdown",
            "value" => docs
          }
        }
      else
        nil
      end
    else
      nil
    end
  end

  # Extract word at position
  defp get_word_at_position(text, line, character) do
    lines = String.split(text, "\n")
    current_line = Enum.at(lines, line, "")

    # Find word boundaries
    before = String.slice(current_line, 0, character) |> String.reverse()
    after_text = String.slice(current_line, character, String.length(current_line))

    start = Regex.run(~r/^[a-zA-Z0-9_$]*/, before) |> List.first() |> String.reverse()
    end_part = Regex.run(~r/^[a-zA-Z0-9_$]*/, after_text) |> List.first()

    word = start <> end_part
    if String.length(word) > 0, do: word, else: nil
  end

  # Zola (Tera) documentation
  defp get_zola_docs(word) do
    docs = %{
      "page" => "**page** - Current page object\n\nContains: `title`, `content`, `date`, `permalink`, `slug`, `path`",
      "section" => "**section** - Current section object\n\nContains: `title`, `description`, `path`, `permalink`, `pages`",
      "config" => "**config** - Site configuration object\n\nAccess config.toml values",
      "title" => "**title** - Page or section title",
      "content" => "**content** - Rendered HTML content",
      "date" => "**date** - Publication date",
      "permalink" => "**permalink** - Full URL to the page",
      "if" => "**if** - Conditional statement\n\nUsage: `{% if condition %}...{% endif %}`",
      "for" => "**for** - Loop statement\n\nUsage: `{% for item in items %}...{% endfor %}`",
      "block" => "**block** - Define content block\n\nUsage: `{% block name %}...{% endblock %}`",
      "extends" => "**extends** - Inherit from base template\n\nUsage: `{% extends \"base.html\" %}`",
      "include" => "**include** - Include another template\n\nUsage: `{% include \"partial.html\" %}`"
    }

    Map.get(docs, word)
  end

  # Hakyll documentation
  defp get_hakyll_docs(word) do
    docs = %{
      "$title$" => "**$title$** - Page title from metadata",
      "$body$" => "**$body$** - Rendered page content",
      "$url$" => "**$url$** - Page URL",
      "$date$" => "**$date$** - Publication date",
      "$author$" => "**$author$** - Page author",
      "title" => "**title** - Page title metadata field",
      "date" => "**date** - Publication date metadata field",
      "author" => "**author** - Author metadata field",
      "tags" => "**tags** - Tags/categories for the page"
    }

    Map.get(docs, word)
  end

  # Franklin.jl documentation
  defp get_franklin_docs(word) do
    docs = %{
      "@def" => "**@def** - Define page variable\n\nUsage: `@def title = \"My Title\"`",
      "title" => "**title** - Page title variable",
      "author" => "**author** - Page author variable",
      "published" => "**published** - Publication date",
      "tags" => "**tags** - Page tags/categories"
    }

    Map.get(docs, word)
  end

  # Generic SSG documentation
  defp get_generic_docs(word) do
    docs = %{
      "title" => "**title** - Page title",
      "date" => "**date** - Publication date",
      "author" => "**author** - Page author",
      "description" => "**description** - Page description for SEO",
      "tags" => "**tags** - Page tags/categories"
    }

    Map.get(docs, word)
  end
end
