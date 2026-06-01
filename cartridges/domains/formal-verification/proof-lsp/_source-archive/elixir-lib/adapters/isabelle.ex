# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyProof.Adapters.Isabelle do
  @moduledoc """
  Adapter for Isabelle - Generic proof assistant.

  ## Commands

  - `isabelle` - Isabelle system command
  - `isabelle build` - Build theories

  ## File Extensions

  - `.thy` - Isabelle theory files
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
    thy_files = Path.wildcard(Path.join(project_path, "**/*.thy"))
    root_exists = File.exists?(Path.join(project_path, "ROOT"))
    {:ok, thy_files != [] || root_exists}
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
    case System.cmd("isabelle", ["version"], stderr_to_stdout: true) do
      {output, 0} ->
        version = output |> String.trim()
        {:ok, version}

      {error, _} ->
        {:error, error}
    end
  end

  @impl PolyProof.Adapters.Behaviour
  def metadata do
    %{
      name: "Isabelle",
      description: "Generic proof assistant with HOL logic",
      file_extensions: [".thy"],
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
    Logger.info("Checking Isabelle proof at #{file_path}")

    timeout = opts[:timeout] || 60_000
    flags = opts[:flags] || []

    # Extract theory name from file path
    theory_name = Path.basename(file_path, ".thy")
    args = ["build", "-D", Path.dirname(file_path)] ++ flags

    case System.cmd("isabelle", args, stderr_to_stdout: true) do
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
    # TODO: Implement using Isabelle/jEdit protocol or PIDE
    Logger.info("Getting goals at #{file_path}:#{line}:#{column}")

    goals = [
      %{
        hypothesis: ["P : bool", "Q : bool"],
        conclusion: "P ∧ Q ⟶ Q ∧ P"
      }
    ]

    {:reply, {:ok, goals}, state}
  end

  @impl true
  def handle_call({:apply_tactic, file_path, line, column, tactic}, _from, state) do
    # TODO: Implement using Isabelle interactive mode
    Logger.info("Applying tactic '#{tactic}' at #{file_path}:#{line}:#{column}")

    new_goals = [
      %{
        hypothesis: ["P : bool", "Q : bool", "H : P ∧ Q"],
        conclusion: "Q ∧ P"
      }
    ]

    {:reply, {:ok, new_goals}, state}
  end

  @impl true
  def handle_call({:search_theorems, query}, _from, state) do
    # TODO: Implement using Isabelle find_theorems command
    Logger.info("Searching theorems matching: #{query}")

    results = [
      "conj_commute : P ∧ Q = Q ∧ P",
      "conj_assoc : (P ∧ Q) ∧ R = P ∧ (Q ∧ R)"
    ]

    {:reply, {:ok, results}, state}
  end
end
