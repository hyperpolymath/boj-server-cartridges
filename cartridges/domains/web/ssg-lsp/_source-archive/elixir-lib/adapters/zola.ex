# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolySSG.Adapters.Zola do
  @moduledoc """
  Adapter for Zola - Fast static site generator written in Rust.

  ## Configuration

  Zola uses `config.toml` at the project root.

  ## Commands

  - `zola build` - Build the site
  - `zola serve` - Start dev server
  - `zola clean` - Remove public/ directory
  """
  use GenServer
  @behaviour PolySSG.Adapters.Behaviour

  require Logger

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl PolySSG.Adapters.Behaviour
  def detect(project_path) do
    config_path = Path.join(project_path, "config.toml")
    {:ok, File.exists?(config_path)}
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
    output_dir = Path.join(project_path, "public")
    File.rm_rf(output_dir)
  end

  @impl PolySSG.Adapters.Behaviour
  def version do
    case System.cmd("zola", ["--version"], stderr_to_stdout: true) do
      {output, 0} ->
        version = output |> String.trim() |> String.replace("zola ", "")
        {:ok, version}

      {error, _} ->
        {:error, error}
    end
  end

  @impl PolySSG.Adapters.Behaviour
  def metadata do
    %{
      name: "Zola",
      language: "Rust",
      description: "Fast static site generator with built-in Sass compilation",
      config_files: ["config.toml"],
      template_dirs: ["templates/"]
    }
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %{builds: %{}, servers: %{}}}
  end

  @impl true
  def handle_call({:build, project_path, opts}, _from, state) do
    Logger.info("Building Zola site at #{project_path}")

    args = ["build"]
    args = if opts[:draft], do: args ++ ["--drafts"], else: args
    args = if opts[:base_url], do: args ++ ["--base-url", opts[:base_url]], else: args

    case System.cmd("zola", args, cd: project_path, stderr_to_stdout: true) do
      {output, 0} ->
        result = %{
          success: true,
          output: output,
          duration: nil
        }

        {:reply, {:ok, result}, state}

      {error, exit_code} ->
        {:reply, {:error, "Build failed (exit #{exit_code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:serve, project_path, opts}, _from, state) do
    Logger.info("Starting Zola dev server at #{project_path}")

    port = opts[:port] || 1111

    # Start server in background
    port_obj = Port.open(
      {:spawn_executable, System.find_executable("zola")},
      [
        :binary,
        :exit_status,
        args: ["serve", "--port", to_string(port)],
        cd: project_path
      ]
    )

    new_state = put_in(state.servers[project_path], {port, port_obj})

    {:reply, {:ok, port}, new_state}
  end
end
