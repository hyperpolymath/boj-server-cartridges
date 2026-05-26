# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolySSG.Adapters.MdBook do
  @moduledoc """
  Adapter for mdBook - Create books from Markdown files (Rust).

  ## Configuration

  mdBook uses `book.toml` at the project root.

  ## Commands

  - `mdbook build` - Build the book
  - `mdbook serve` - Start dev server
  - `mdbook clean` - Remove build directory
  """
  use GenServer
  @behaviour PolySSG.Adapters.Behaviour

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl PolySSG.Adapters.Behaviour
  def detect(project_path) do
    book_toml = Path.join(project_path, "book.toml")
    {:ok, File.exists?(book_toml)}
  end

  @impl PolySSG.Adapters.Behaviour
  def build(project_path, opts) do
    GenServer.call(__MODULE__, {:build, project_path, opts})
  end

  @impl PolySSG.Adapters.Behaviour
  def serve(project_path, opts) do
    GenServer.call(__MODULE__, {:serve, project_path, opts})
  end

  @impl PolySSG.Adapters.Behaviour
  def clean(project_path) do
    case System.cmd("mdbook", ["clean"], cd: project_path) do
      {_, 0} -> :ok
      {error, _} -> {:error, error}
    end
  end

  @impl PolySSG.Adapters.Behaviour
  def version do
    case System.cmd("mdbook", ["--version"], stderr_to_stdout: true) do
      {output, 0} ->
        version = output |> String.trim() |> String.replace("mdbook v", "")
        {:ok, version}

      {error, _} ->
        {:error, error}
    end
  end

  @impl PolySSG.Adapters.Behaviour
  def metadata do
    %{
      name: "mdBook",
      language: "Rust",
      description: "Create books from Markdown files",
      config_files: ["book.toml"],
      template_dirs: ["theme/"]
    }
  end

  # Server callbacks

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_call({:build, project_path, _opts}, _from, state) do
    Logger.info("Building mdBook at #{project_path}")

    case System.cmd("mdbook", ["build"], cd: project_path, stderr_to_stdout: true) do
      {output, 0} ->
        {:reply, {:ok, %{success: true, output: output}}, state}

      {error, code} ->
        {:reply, {:error, "Build failed (exit #{code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:serve, project_path, opts}, _from, state) do
    Logger.info("Starting mdBook dev server at #{project_path}")

    port = opts[:port] || 3000

    port_obj = Port.open(
      {:spawn_executable, System.find_executable("mdbook")},
      [:binary, :exit_status, args: ["serve", "--port", to_string(port)], cd: project_path]
    )

    {:reply, {:ok, port}, Map.put(state, :server_port, port_obj)}
  end
end
