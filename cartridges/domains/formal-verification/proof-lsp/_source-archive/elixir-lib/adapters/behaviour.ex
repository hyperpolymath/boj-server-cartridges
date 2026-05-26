# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyProof.Adapters.Behaviour do
  @moduledoc """
  Behaviour defining the contract for proof assistant adapters.

  Each adapter implements this behaviour to provide a consistent interface
  for detecting, checking proofs, displaying goals, and interacting with
  proof assistants.

  ## Example

      defmodule PolyProof.Adapters.Coq do
        use GenServer
        @behaviour PolyProof.Adapters.Behaviour

        @impl true
        def detect(project_path) do
          has_coq_files = Path.wildcard(Path.join(project_path, "**/*.v")) != []
          {:ok, has_coq_files}
        end

        @impl true
        def check_proof(file_path, opts) do
          # Run coqc to check proof
        end
      end
  """

  @type file_path :: String.t()
  @type project_path :: String.t()
  @type proof_opts :: keyword()
  @type proof_result :: {:ok, map()} | {:error, String.t()}
  @type detect_result :: {:ok, boolean()} | {:error, String.t()}
  @type goals :: [%{hypothesis: [String.t()], conclusion: String.t()}]
  @type tactic_result :: {:ok, goals()} | {:error, String.t()}

  @doc """
  Detect if this proof assistant is present in the project directory.

  Returns `{:ok, true}` if proof files exist, `{:ok, false}` otherwise.
  """
  @callback detect(project_path) :: detect_result

  @doc """
  Check a proof file for correctness.

  ## Options

  - `:timeout` - Max time for proof checking (milliseconds)
  - `:flags` - Additional flags to pass to proof checker

  Returns `{:ok, result}` with compilation output or `{:error, reason}`.
  """
  @callback check_proof(file_path, proof_opts) :: proof_result

  @doc """
  Get current proof goals at a specific position in the file.

  Returns list of goals with hypotheses and conclusions.
  """
  @callback get_goals(file_path, line :: pos_integer(), column :: pos_integer()) :: {:ok, goals()} | {:error, String.t()}

  @doc """
  Apply a tactic at a specific position and return resulting goals.

  ## Example

      apply_tactic("example.v", 42, 10, "intros x y")
      # => {:ok, [%{hypothesis: ["x : nat", "y : nat"], conclusion: "x + y = y + x"}]}
  """
  @callback apply_tactic(file_path, line :: pos_integer(), column :: pos_integer(), tactic :: String.t()) :: tactic_result

  @doc """
  Search for theorems matching a pattern or type signature.

  ## Example

      search_theorems("_ + _ = _ + _")
      # => {:ok, ["Nat.add_comm : forall n m, n + m = m + n", ...]}
  """
  @callback search_theorems(query :: String.t()) :: {:ok, [String.t()]} | {:error, String.t()}

  @doc """
  Get proof assistant version.
  """
  @callback version() :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Get proof assistant metadata (name, description, file extensions).
  """
  @callback metadata() :: %{
              name: String.t(),
              description: String.t(),
              file_extensions: [String.t()],
              interactive_mode: boolean()
            }
end
