# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyProof.LSP.Handlers.Hover do
  @moduledoc """
  Provides hover documentation for proof assistants.

  Shows:
  - Tactic documentation
  - Theorem statements
  - Type information
  - Proof state hints
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
      # Get documentation based on prover and word
      docs = case assigns.detected_prover do
        :coq -> get_coq_docs(word)
        :lean -> get_lean_docs(word)
        :isabelle -> get_isabelle_docs(word)
        :agda -> get_agda_docs(word)
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

    # Find word boundaries (including underscores)
    before = String.slice(current_line, 0, character) |> String.reverse()
    after_text = String.slice(current_line, character, String.length(current_line))

    start = Regex.run(~r/^[a-zA-Z0-9_]*/, before) |> List.first() |> String.reverse()
    end_part = Regex.run(~r/^[a-zA-Z0-9_]*/, after_text) |> List.first()

    word = start <> end_part
    if String.length(word) > 0, do: word, else: nil
  end

  # Coq documentation
  defp get_coq_docs(word) do
    docs = %{
      "intro" => "**intro** - Introduce hypothesis\n\nMoves a premise from the goal into the context.\n\nExample: `intro H`",
      "intros" => "**intros** - Introduce multiple hypotheses\n\nMoves all premises into the context.\n\nExample: `intros x y H`",
      "apply" => "**apply** - Apply theorem or hypothesis\n\nApplies a theorem to solve or transform the goal.\n\nExample: `apply plus_comm`",
      "exact" => "**exact** - Provide exact proof term\n\nDirectly provides the proof term for the goal.\n\nExample: `exact H`",
      "assumption" => "**assumption** - Use hypothesis as proof\n\nSolves goal using an exact hypothesis from context.",
      "reflexivity" => "**reflexivity** - Prove equality by reflexivity\n\nProves goals of the form `x = x`.",
      "symmetry" => "**symmetry** - Swap equality sides\n\nTransforms `x = y` into `y = x`.",
      "transitivity" => "**transitivity** - Apply transitivity\n\nFor equality or order relations.",
      "simpl" => "**simpl** - Simplify expression\n\nEvaluates functions and simplifies terms.",
      "unfold" => "**unfold** - Unfold definition\n\nReplaces a defined constant with its definition.\n\nExample: `unfold plus`",
      "rewrite" => "**rewrite** - Rewrite using equality\n\nReplaces terms using an equality hypothesis.\n\nExample: `rewrite H`",
      "induction" => "**induction** - Proof by induction\n\nApplies induction principle.\n\nExample: `induction n`",
      "destruct" => "**destruct** - Case analysis\n\nPerforms case analysis on a term.\n\nExample: `destruct x`",
      "split" => "**split** - Split conjunction\n\nSplits `A /\\ B` into two subgoals.",
      "left" => "**left** - Prove left disjunct\n\nFor goal `A \\/ B`, proves `A`.",
      "right" => "**right** - Prove right disjunct\n\nFor goal `A \\/ B`, proves `B`.",
      "exists" => "**exists** - Provide witness\n\nProvides witness for existential quantification.\n\nExample: `exists 0`",
      "auto" => "**auto** - Automatic proof search\n\nAutomatically tries to solve goal.",
      "eauto" => "**eauto** - Enhanced automatic proof\n\nMore powerful version of auto with existentials."
    }

    Map.get(docs, word)
  end

  # Lean documentation
  defp get_lean_docs(word) do
    docs = %{
      "intro" => "**intro** - Introduce variable\n\nIntroduces a variable or hypothesis.",
      "intros" => "**intros** - Introduce multiple variables\n\nIntroduces multiple variables at once.",
      "apply" => "**apply** - Apply theorem\n\nApplies a theorem to the current goal.",
      "exact" => "**exact** - Provide exact term\n\nProvides the exact proof term.",
      "assumption" => "**assumption** - Use assumption\n\nCloses goal using an assumption.",
      "rfl" => "**rfl** - Reflexivity\n\nProves equality by reflexivity.",
      "simp" => "**simp** - Simplification\n\nSimplifies goal using simp lemmas.",
      "rewrite" => "**rewrite** - Rewrite with equality\n\nRewrites goal using an equality.\n\nAlias: `rw`",
      "rw" => "**rw** - Rewrite (short form)\n\nShort form of rewrite.",
      "calc" => "**calc** - Calculational proof\n\nStructured chain of equalities or inequalities.",
      "have" => "**have** - Introduce lemma\n\nIntroduces an intermediate lemma.",
      "show" => "**show** - Explicit goal\n\nMakes the goal explicit before proving it.",
      "cases" => "**cases** - Case analysis\n\nPerforms case analysis on a term.",
      "induction" => "**induction** - Induction\n\nApplies induction principle.",
      "split" => "**split** - Split conjunction\n\nSplits goal into subgoals.",
      "ring" => "**ring** - Ring tactic\n\nSolves equations in commutative rings.",
      "linarith" => "**linarith** - Linear arithmetic\n\nSolves linear arithmetic goals.",
      "omega" => "**omega** - Presburger arithmetic\n\nSolves Presburger arithmetic goals."
    }

    Map.get(docs, word)
  end

  # Isabelle documentation
  defp get_isabelle_docs(word) do
    docs = %{
      "rule" => "**rule** - Apply rule\n\nApplies an introduction or elimination rule.",
      "erule" => "**erule** - Elimination rule\n\nApplies an elimination rule.",
      "simp" => "**simp** - Simplification\n\nSimplifies goal using simplifier.",
      "auto" => "**auto** - Automatic proof\n\nAutomatic proof method combining simplification and classical reasoning.",
      "blast" => "**blast** - Tableau prover\n\nFast automatic prover for first-order logic.",
      "fast" => "**fast** - Fast prover\n\nFast classical reasoning.",
      "force" => "**force** - Forceful simplification\n\nCombines simplification with classical reasoning.",
      "intro" => "**intro** - Introduction rules\n\nApplies introduction rules.",
      "elim" => "**elim** - Elimination rules\n\nApplies elimination rules.",
      "induct" => "**induct** - Induction\n\nApplies induction principle.",
      "by" => "**by** - Proof method\n\nCompletes proof using specified method.\n\nExample: `by simp`",
      "apply" => "**apply** - Apply method\n\nApplies proof method to current goal.",
      "done" => "**done** - Finish proof\n\nCompletes the proof.",
      "sorry" => "**sorry** - Admit proof\n\nAdmits the goal without proof (unsafe)."
    }

    Map.get(docs, word)
  end

  # Agda documentation
  defp get_agda_docs(word) do
    docs = %{
      "data" => "**data** - Define datatype\n\nDefines an inductive datatype.\n\nExample: `data Nat : Set where ...`",
      "record" => "**record** - Define record type\n\nDefines a record (product type).",
      "postulate" => "**postulate** - Assume axiom\n\nPostulates a constant without definition.",
      "open" => "**open** - Open module\n\nBrings module contents into scope.",
      "import" => "**import** - Import module\n\nImports a module.",
      "where" => "**where** - Definition body\n\nIntroduces definition or proof body.",
      "with" => "**with** - Pattern matching helper\n\nAuxiliary pattern matching construct.",
      "rewrite" => "**rewrite** - Rewrite with equality\n\nRewrites goal using an equality.",
      "Set" => "**Set** - Universe of types\n\nThe universe of small types.",
      "Prop" => "**Prop** - Propositions\n\nThe universe of propositions (if enabled).",
      "Type" => "**Type** - Large universe\n\nLarge universe level.",
      "Level" => "**Level** - Universe level\n\nRepresents universe levels."
    }

    Map.get(docs, word)
  end

  # Generic proof assistant documentation
  defp get_generic_docs(word) do
    docs = %{
      "intro" => "**intro** - Introduce hypothesis\n\nIntroduces a hypothesis or variable.",
      "apply" => "**apply** - Apply theorem\n\nApplies a theorem to the goal.",
      "rewrite" => "**rewrite** - Rewrite with equality\n\nRewrites using an equality.",
      "induction" => "**induction** - Proof by induction\n\nApplies induction principle.",
      "reflexivity" => "**reflexivity** - Prove by reflexivity\n\nProves equality by reflexivity."
    }

    Map.get(docs, word)
  end
end
