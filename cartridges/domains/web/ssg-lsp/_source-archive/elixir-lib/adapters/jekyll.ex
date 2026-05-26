# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolySSG.Adapters.Jekyll do
  @moduledoc """
  Adapter for Jekyll - Transform plain text into static websites (Ruby).

  ## Configuration

  Jekyll uses `_config.yml` at the project root.

  ## Commands

  - `jekyll build` - Build the site
  - `jekyll serve` - Start dev server
  - `jekyll clean` - Remove build directory
  """
  use GenServer
  @behaviour PolySSG.Adapters.Behaviour

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl PolySSG.Adapters.Behaviour
  def detect(project_path) do
    config_yml = Path.join(project_path, "_config.yml")
    gemfile = Path.join(project_path, "Gemfile")

    # Jekyll detected if _config.yml exists or Gemfile mentions jekyll
    detected =
      File.exists?(config_yml) or
        (File.exists?(gemfile) and File.read!(gemfile) =~ ~r/jekyll/)

    {:ok, detected}
  end

  @impl PolySSG.Adapters.Behaviour
  def build(project_path, opts) do
    GenServer.call(__MODULE__, {:build, project_path, opts}, 120_000)
  end

  @impl PolySSG.Adapters.Behaviour
  def serve(project_path, opts) do
    GenServer.call(__MODULE__, {:serve, project_path, opts})
  end

  @impl PolySSG.Adapters.Behaviour
  def clean(project_path) do
    case System.cmd("jekyll", ["clean"], cd: project_path) do
      {_, 0} -> :ok
      {error, _} -> {:error, error}
    end
  end

  @impl PolySSG.Adapters.Behaviour
  def version do
    case System.cmd("jekyll", ["--version"], stderr_to_stdout: true) do
      {output, 0} ->
        version = output |> String.trim() |> String.replace("jekyll ", "")
        {:ok, version}

      {error, _} ->
        {:error, error}
    end
  end

  @impl PolySSG.Adapters.Behaviour
  def metadata do
    %{
      name: "Jekyll",
      language: "Ruby",
      description: "Transform plain text into static websites and blogs",
      config_files: ["_config.yml", "Gemfile"],
      template_dirs: ["_layouts/", "_includes/"]
    }
  end

  # Server callbacks

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_call({:build, project_path, opts}, _from, state) do
    Logger.info("Building Jekyll site at #{project_path}")

    args = ["build"]
    args = if opts[:drafts], do: args ++ ["--drafts"], else: args
    args = if opts[:future], do: args ++ ["--future"], else: args

    case System.cmd("jekyll", args, cd: project_path, stderr_to_stdout: true) do
      {output, 0} ->
        {:reply, {:ok, %{success: true, output: output}}, state}

      {error, code} ->
        {:reply, {:error, "Build failed (exit #{code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:serve, project_path, opts}, _from, state) do
    Logger.info("Starting Jekyll dev server at #{project_path}")

    port = opts[:port] || 4000

    port_obj = Port.open(
      {:spawn_executable, System.find_executable("jekyll")},
      [:binary, :exit_status, args: ["serve", "--port", to_string(port)], cd: project_path]
    )

    {:reply, {:ok, port}, Map.put(state, :server_port, port_obj)}
  end
end
