# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyProof.LSP.Handlers.Completion do
  @moduledoc """
  Provides auto-completion for proof assistants.

  Supports:
  - Coq tactics and commands
  - Lean tactics and definitions
  - Isabelle methods and commands
  - Agda constructors and functions
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

    # Provide completions based on context and detected prover
    completions = case assigns.detected_prover do
      :coq -> complete_coq(context)
      :lean -> complete_lean(context)
      :isabelle -> complete_isabelle(context)
      :agda -> complete_agda(context)
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

  # Detect completion trigger
  defp get_trigger(text) do
    cond do
      String.match?(text, ~r/Proof\.\s*$/) -> :proof_start
      String.match?(text, ~r/by\s+$/) -> :tactic
      String.match?(text, ~r/apply\s+$/) -> :theorem_name
      String.ends_with?(text, ":") -> :type_annotation
      true -> :none
    end
  end

  # Coq completions
  defp complete_coq(context) do
    case context.trigger do
      :proof_start ->
        [
          "intro", "intros", "apply", "exact", "reflexivity",
          "simpl", "unfold", "rewrite", "induction", "destruct"
        ]
        |> Enum.map(&create_completion_item(&1, "keyword"))

      :tactic ->
        [
          "intro", "intros", "apply", "exact", "assumption",
          "reflexivity", "symmetry", "transitivity",
          "split", "left", "right", "exists",
          "simpl", "unfold", "fold", "compute",
          "rewrite", "replace", "induction", "destruct",
          "auto", "eauto", "trivial", "omega"
        ]
        |> Enum.map(&create_completion_item(&1, "keyword"))

      _ ->
        [
          "Theorem", "Lemma", "Definition", "Fixpoint", "Inductive",
          "Record", "Class", "Instance", "Proof", "Qed",
          "Admitted", "Abort"
        ]
        |> Enum.map(&create_completion_item(&1, "keyword"))
    end
  end

  # Lean completions
  defp complete_lean(context) do
    case context.trigger do
      :tactic ->
        [
          "intro", "intros", "apply", "exact", "assumption",
          "rfl", "simp", "rewrite", "rw", "calc",
          "have", "show", "suffices",
          "cases", "induction", "split",
          "ring", "linarith", "omega"
        ]
        |> Enum.map(&create_completion_item(&1, "keyword"))

      :type_annotation ->
        ["Prop", "Type", "Sort", "Nat", "Int", "List", "Option"]
        |> Enum.map(&create_completion_item(&1, "class"))

      _ ->
        [
          "theorem", "lemma", "def", "example",
          "inductive", "structure", "class", "instance",
          "axiom", "constant", "variable",
          "import", "open", "namespace"
        ]
        |> Enum.map(&create_completion_item(&1, "keyword"))
    end
  end

  # Isabelle completions
  defp complete_isabelle(context) do
    case context.trigger do
      :tactic ->
        [
          "rule", "erule", "drule", "frule",
          "simp", "auto", "blast", "fast", "force",
          "clarify", "safe", "intro", "elim",
          "induct", "coinduct"
        ]
        |> Enum.map(&create_completion_item(&1, "keyword"))

      _ ->
        [
          "theory", "imports", "begin", "end",
          "lemma", "theorem", "corollary",
          "definition", "fun", "datatype",
          "proof", "qed", "sorry",
          "by", "apply", "done"
        ]
        |> Enum.map(&create_completion_item(&1, "keyword"))
    end
  end

  # Agda completions
  defp complete_agda(context) do
    case context.trigger do
      :type_annotation ->
        ["Set", "Prop", "Type", "Level", "Bool", "Nat", "List"]
        |> Enum.map(&create_completion_item(&1, "class"))

      _ ->
        [
          "data", "record", "postulate", "primitive",
          "open", "import", "module",
          "where", "with", "rewrite",
          "pattern", "constructor",
          "abstract", "private", "public"
        ]
        |> Enum.map(&create_completion_item(&1, "keyword"))
    end
  end

  # Generic proof assistant completions
  defp complete_generic(context) do
    case context.trigger do
      :tactic ->
        ["intro", "apply", "rewrite", "induction", "reflexivity"]
        |> Enum.map(&create_completion_item(&1, "keyword"))

      _ ->
        ["theorem", "lemma", "proof", "qed"]
        |> Enum.map(&create_completion_item(&1, "keyword"))
    end
  end

  # Create LSP completion item
  defp create_completion_item(label, kind_str) do
    kind = case kind_str do
      "keyword" -> 14    # Keyword
      "class" -> 7       # Class
      _ -> 1             # Text
    end

    %{
      "label" => label,
      "kind" => kind,
      "detail" => "#{kind_str}",
      "insertText" => label
    }
  end
end
