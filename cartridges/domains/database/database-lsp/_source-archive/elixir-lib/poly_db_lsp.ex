defmodule PolyDb.Lsp do
  @moduledoc """
  Elixir Language Server for PolyDb.
  Lints SQL queries in code against the V-lang Triple Adapter.
  """

  use GenServer

  @type state :: %{
          adapter_url: String.t(),
          diagnostics: map()
        }

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    adapter_url = Keyword.get(opts, :adapter_url, "http://localhost:5433")
    {:ok, %{adapter_url: adapter_url, diagnostics: %{}}}
  end

  def lint(file_path, content) do
    GenServer.call(__MODULE__, {:lint, file_path, content})
  end

  @impl true
  def handle_call({:lint, file_path, _content}, _from, state) do
    # Mock finding for demonstration:
    finding = %{
      range: %{start: %{line: 0, character: 0}, end: %{line: 0, character: 10}},
      severity: 1, # Error
      source: "Idris2 ABI",
      message: "SQL Injection risk detected: Multiple statements in single query (';' forbidden)."
    }

    {:reply, {:ok, [finding]}, state}
  end
end
