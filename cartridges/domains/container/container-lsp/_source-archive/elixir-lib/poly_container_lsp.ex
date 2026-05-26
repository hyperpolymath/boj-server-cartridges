defmodule PolyContainer.Lsp do
  @moduledoc """
  Elixir Language Server for PolyContainer.
  Lints compose.toml and Containerfile against the V-lang Triple Adapter.
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
    # Default to V-lang Triple Adapter (REST port)
    adapter_url = Keyword.get(opts, :adapter_url, "http://localhost:8083")
    {:ok, %{adapter_url: adapter_url, diagnostics: %{}}}
  end

  @doc """
  Lint a document (e.g., compose.toml) by sending it to the V-lang adapter's
  validation endpoint.
  """
  def lint(file_path, content) do
    GenServer.call(__MODULE__, {:lint, file_path, content})
  end

  @impl true
  def handle_call({:lint, file_path, _content}, _from, state) do
    # 1. Call V-lang REST endpoint: POST /validate
    # 2. Map V-lang/Zig findings to LSP Diagnostic objects
    # 3. Return the diagnostics

    # Mock finding for demonstration:
    finding = %{
      range: %{start: %{line: 0, character: 0}, end: %{line: 0, character: 10}},
      severity: 1, # Error
      source: "Idris2 ABI",
      message: "Container image MUST be cgr.dev/chainguard/wolfi-base"
    }

    {:reply, {:ok, [finding]}, state}
  end
end
