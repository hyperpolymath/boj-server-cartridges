# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolySSG.Adapters.Hugo do
  @moduledoc """
  Adapter for Hugo - Fast and flexible static site generator written in Go.

  ## Configuration

  Hugo uses `config.toml`, `config.yaml`, or `config.json`.

  ## Commands

  - `hugo` - Build the site
  - `hugo server` - Start dev server
  - `hugo --cleanDestinationDir` - Clean and build
  """
  use GenServer
  @behaviour PolySSG.Adapters.Behaviour

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl PolySSG.Adapters.Behaviour
  def detect(project_path) do
    config_files = ["config.toml", "config.yaml", "config.json", "hugo.toml"]

    detected =
      Enum.any?(config_files, fn file ->
        Path.join(project_path, file) |> File.exists?()
      end)

    {:ok, detected}
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
    public_dir = Path.join(project_path, "public")
    File.rm_rf(public_dir)
  end

  @impl PolySSG.Adapters.Behaviour
  def version do
    case System.cmd("hugo", ["version"], stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {error, _} -> {:error, error}
    end
  end

  @impl PolySSG.Adapters.Behaviour
  def metadata do
    %{
      name: "Hugo",
      language: "Go",
      description: "Fast and flexible static site generator",
      config_files: ["config.toml", "config.yaml", "config.json", "hugo.toml"],
      template_dirs: ["layouts/", "themes/"]
    }
  end

  # Server callbacks

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_call({:build, project_path, opts}, _from, state) do
    Logger.info("Building Hugo site at #{project_path}")

    args = []
    args = if opts[:drafts], do: args ++ ["--buildDrafts"], else: args
    args = if opts[:future], do: args ++ ["--buildFuture"], else: args
    args = if opts[:minify], do: args ++ ["--minify"], else: args

    case System.cmd("hugo", args, cd: project_path, stderr_to_stdout: true) do
      {output, 0} ->
        {:reply, {:ok, %{success: true, output: output}}, state}

      {error, code} ->
        {:reply, {:error, "Build failed (exit #{code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:serve, project_path, opts}, _from, state) do
    Logger.info("Starting Hugo dev server at #{project_path}")

    port = opts[:port] || 1313

    port_obj = Port.open(
      {:spawn_executable, System.find_executable("hugo")},
      [:binary, :exit_status, args: ["server", "--port", to_string(port)], cd: project_path]
    )

    {:reply, {:ok, port}, Map.put(state, :server_port, port_obj)}
  end
end
