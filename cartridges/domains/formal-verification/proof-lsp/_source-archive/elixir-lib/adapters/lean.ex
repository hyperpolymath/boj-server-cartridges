# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyProof.Adapters.Lean do
  @moduledoc """
  Adapter for Lean - Theorem prover and programming language.

  ## Commands

  - `lean` - Lean compiler and prover

  ## File Extensions

  - `.lean` - Lean source files
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
    lean_files = Path.wildcard(Path.join(project_path, "**/*.lean"))
    lakefile_exists = File.exists?(Path.join(project_path, "lakefile.lean"))
    {:ok, lean_files != [] || lakefile_exists}
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
    case System.cmd("lean", ["--version"], stderr_to_stdout: true) do
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
      name: "Lean",
      description: "Functional programming language and theorem prover",
      file_extensions: [".lean"],
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
    Logger.info("Checking Lean proof at #{file_path}")

    timeout = opts[:timeout] || 30_000
    flags = opts[:flags] || []

    args = [file_path] ++ flags

    case System.cmd("lean", args, stderr_to_stdout: true) do
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
    # TODO: Implement using Lean LSP server or --info flag
    Logger.info("Getting goals at #{file_path}:#{line}:#{column}")

    goals = [
      %{
        hypothesis: ["α : Type", "a : α"],
        conclusion: "a = a"
      }
    ]

    {:reply, {:ok, goals}, state}
  end

  @impl true
  def handle_call({:apply_tactic, file_path, line, column, tactic}, _from, state) do
    # TODO: Implement using Lean interactive mode
    Logger.info("Applying tactic '#{tactic}' at #{file_path}:#{line}:#{column}")

    new_goals = []

    {:reply, {:ok, new_goals}, state}
  end

  @impl true
  def handle_call({:search_theorems, query}, _from, state) do
    # TODO: Implement using Lean library search
    Logger.info("Searching theorems matching: #{query}")

    results = [
      "Eq.refl : ∀ {α : Type} (a : α), a = a",
      "Eq.symm : ∀ {α : Type} {a b : α}, a = b → b = a"
    ]

    {:reply, {:ok, results}, state}
  end
end
