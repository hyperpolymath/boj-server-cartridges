# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyProof.Adapters.Agda do
  @moduledoc """
  Adapter for Agda - Dependently typed functional programming language.

  ## Commands

  - `agda` - Agda compiler and type checker

  ## File Extensions

  - `.agda` - Agda source files
  - `.lagda` - Literate Agda files
  - `.lagda.md` - Literate Agda with Markdown
  """
  use GenServer
  @behaviour PolyProof.Adapters.Behaviour

  require Logger

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl PolyProof.Adapters.Behaviour
  def detect(project_path) do
    agda_files =
      Path.wildcard(Path.join(project_path, "**/*.agda")) ++
      Path.wildcard(Path.join(project_path, "**/*.lagda")) ++
      Path.wildcard(Path.join(project_path, "**/*.lagda.md"))

    {:ok, agda_files != []}
  end

  @impl PolyProof.Adapters.Behaviour
  def check_proof(file_path, opts) do
    GenServer.call(__MODULE__, {:check_proof, file_path, opts})
  end

  @impl PolyProof.Adapters.Behaviour
  def get_goals(file_path, line, column) do
    GenServer.call(__MODULE__, {:get_goals, file_path, line, column})
  end

  @impl PolyProof.Adapters.Behaviour
  def apply_tactic(file_path, line, column, tactic) do
    GenServer.call(__MODULE__, {:apply_tactic, file_path, line, column, tactic})
  end

  @impl PolyProof.Adapters.Behaviour
  def search_theorems(query) do
    GenServer.call(__MODULE__, {:search_theorems, query})
  end

  @impl PolyProof.Adapters.Behaviour
  def version do
    case System.cmd("agda", ["--version"], stderr_to_stdout: true) do
      {output, 0} ->
        version = output |> String.split("\n") |> List.first() |> String.trim()
        {:ok, version}

      {error, _} ->
        {:error, error}
    end
  end

  @impl PolyProof.Adapters.Behaviour
  def metadata do
    %{
      name: "Agda",
      description: "Dependently typed functional programming language and proof assistant",
      file_extensions: [".agda", ".lagda", ".lagda.md"],
      interactive_mode: true
    }
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %{sessions: %{}, goals: %{}}}
  end

  @impl true
  def handle_call({:check_proof, file_path, opts}, _from, state) do
    Logger.info("Checking Agda proof at #{file_path}")

    timeout = opts[:timeout] || 60_000
    flags = opts[:flags] || []

    args = [file_path] ++ flags

    case System.cmd("agda", args, stderr_to_stdout: true) do
      {output, 0} ->
        result = %{
          success: true,
          output: output,
          errors: []
        }

        {:reply, {:ok, result}, state}

      {error, exit_code} ->
        {:reply, {:error, "Proof checking failed (exit #{exit_code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:get_goals, file_path, line, column}, _from, state) do
    # TODO: Implement using Agda interactive mode
    Logger.info("Getting goals at #{file_path}:#{line}:#{column}")

    goals = [
      %{
        hypothesis: ["A : Set", "x : A"],
        conclusion: "A"
      }
    ]

    {:reply, {:ok, goals}, state}
  end

  @impl true
  def handle_call({:apply_tactic, file_path, line, column, tactic}, _from, state) do
    # TODO: Implement using Agda interactive commands
    # Note: Agda has limited tactic support compared to Coq/Lean
    Logger.info("Applying command '#{tactic}' at #{file_path}:#{line}:#{column}")

    new_goals = []

    {:reply, {:ok, new_goals}, state}
  end

  @impl true
  def handle_call({:search_theorems, query}, _from, state) do
    # TODO: Implement using Agda library search
    Logger.info("Searching definitions matching: #{query}")

    results = [
      "refl : {A : Set} {x : A} → x ≡ x",
      "sym : {A : Set} {x y : A} → x ≡ y → y ≡ x"
    ]

    {:reply, {:ok, results}, state}
  end
end
