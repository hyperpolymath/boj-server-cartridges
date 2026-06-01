# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolySSG.Adapters.Franklin do
  @moduledoc """
  Adapter for Franklin.jl - Julia static site generator.

  ## Configuration

  Franklin uses `config.md` at the project root.

  ## Commands

  - `julia -e 'using Franklin; serve()'` - Build and serve
  - `julia -e 'using Franklin; optimize()'` - Production build
  """
  use GenServer
  @behaviour PolySSG.Adapters.Behaviour

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl PolySSG.Adapters.Behaviour
  def detect(project_path) do
    config_md = Path.join(project_path, "config.md")
    {:ok, File.exists?(config_md)}
  end

  @impl PolySSG.Adapters.Behaviour
  def build(project_path, opts) do
    GenServer.call(__MODULE__, {:build, project_path, opts}, 120_000)
  end

  @impl PolySSG.Adapters.Behaviour
  def serve(project_path, _opts) do
    GenServer.call(__MODULE__, {:serve, project_path})
  end

  @impl PolySSG.Adapters.Behaviour
  def clean(project_path) do
    # Franklin caches in __site/
    cache_dir = Path.join(project_path, "__site")
    File.rm_rf(cache_dir)
  end

  @impl PolySSG.Adapters.Behaviour
  def version do
    julia_code = "using Pkg; println(Pkg.status(\"Franklin\"))"

    case System.cmd("julia", ["-e", julia_code], stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, output |> String.trim()}

      {error, _} ->
        {:error, error}
    end
  end

  @impl PolySSG.Adapters.Behaviour
  def metadata do
    %{
      name: "Franklin.jl",
      language: "Julia",
      description: "Static site generator with Julia code execution",
      config_files: ["config.md"],
      template_dirs: ["_layout/", "_css/"]
    }
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:build, project_path, opts}, _from, state) do
    Logger.info("Building Franklin site at #{project_path}")

    mode = if opts[:production], do: "optimize", else: "publish"
    julia_code = "using Franklin; #{mode}()"

    case System.cmd("julia", ["-e", julia_code], cd: project_path, stderr_to_stdout: true) do
      {output, 0} ->
        {:reply, {:ok, %{success: true, output: output}}, state}

      {error, code} ->
        {:reply, {:error, "Build failed (exit #{code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:serve, project_path}, _from, state) do
    Logger.info("Starting Franklin dev server at #{project_path}")

    julia_code = "using Franklin; serve()"

    port_obj = Port.open(
      {:spawn_executable, System.find_executable("julia")},
      [:binary, :exit_status, args: ["-e", julia_code], cd: project_path]
    )

    # Franklin typically uses port 8000
    {:reply, {:ok, 8000}, Map.put(state, :server_port, port_obj)}
  end
end
