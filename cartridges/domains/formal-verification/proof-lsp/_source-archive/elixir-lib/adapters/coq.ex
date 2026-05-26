# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyProof.Adapters.Coq do
  @moduledoc """
  Adapter for Coq - Interactive theorem prover.

  ## Commands

  - `coqc` - Compile and check proof files
  - `coqtop` - Interactive proof assistant

  ## File Extensions

  - `.v` - Coq source files
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
    coq_files = Path.wildcard(Path.join(project_path, "**/*.v"))
    {:ok, coq_files != []}
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
    case System.cmd("coqc", ["--version"], stderr_to_stdout: true) do
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
      name: "Coq",
      description: "Interactive theorem prover with dependent types",
      file_extensions: [".v"],
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
    Logger.info("Checking Coq proof at #{file_path}")

    timeout = opts[:timeout] || 30_000
    flags = opts[:flags] || []

    args = [file_path] ++ flags

    case System.cmd("coqc", args, stderr_to_stdout: true) do
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
    # TODO: Implement using coqtop interactive mode
    # This requires parsing the file up to the position and querying coqtop
    Logger.info("Getting goals at #{file_path}:#{line}:#{column}")

    goals = [
      %{
        hypothesis: ["H : nat", "n : nat"],
        conclusion: "n + 0 = n"
      }
    ]

    {:reply, {:ok, goals}, state}
  end

  @impl true
  def handle_call({:apply_tactic, file_path, line, column, tactic}, _from, state) do
    # TODO: Implement using coqtop interactive mode
    Logger.info("Applying tactic '#{tactic}' at #{file_path}:#{line}:#{column}")

    new_goals = [
      %{
        hypothesis: ["H : nat", "n : nat", "IHn : n + 0 = n"],
        conclusion: "S n + 0 = S n"
      }
    ]

    {:reply, {:ok, new_goals}, state}
  end

  @impl true
  def handle_call({:search_theorems, query}, _from, state) do
    # TODO: Implement using coqtop Search command
    Logger.info("Searching theorems matching: #{query}")

    results = [
      "Nat.add_0_r : forall n : nat, n + 0 = n",
      "Nat.add_comm : forall n m : nat, n + m = m + n"
    ]

    {:reply, {:ok, results}, state}
  end
end
