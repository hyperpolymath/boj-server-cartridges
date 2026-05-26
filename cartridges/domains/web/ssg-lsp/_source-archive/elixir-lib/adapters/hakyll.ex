# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolySSG.Adapters.Hakyll do
  @moduledoc """
  Adapter for Hakyll - Haskell static site generator.

  ## Configuration

  Hakyll uses a Haskell program (typically `site.hs`) for configuration.

  ## Commands

  - `./site build` - Build the site
  - `./site watch` - Watch and rebuild
  - `./site clean` - Remove _site/ and _cache/
  """
  use GenServer
  @behaviour PolySSG.Adapters.Behaviour

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl PolySSG.Adapters.Behaviour
  def detect(project_path) do
    site_hs = Path.join(project_path, "site.hs")
    cabal_file = Path.join(project_path, "*.cabal") |> Path.wildcard() |> List.first()

    detected = File.exists?(site_hs) or cabal_file != nil
    {:ok, detected}
  end

  @impl PolySSG.Adapters.Behaviour
  def build(project_path, opts) do
    GenServer.call(__MODULE__, {:build, project_path, opts}, 60_000)
  end

  @impl PolySSG.Adapters.Behaviour
  def serve(project_path, _opts) do
    GenServer.call(__MODULE__, {:watch, project_path})
  end

  @impl PolySSG.Adapters.Behaviour
  def clean(project_path) do
    site_bin = Path.join(project_path, "site")

    if File.exists?(site_bin) do
      System.cmd(site_bin, ["clean"], cd: project_path)
      :ok
    else
      {:error, "site binary not found (run 'cabal build' first)"}
    end
  end

  @impl PolySSG.Adapters.Behaviour
  def version do
    # Hakyll version is in the site binary
    {:ok, "unknown"}
  end

  @impl PolySSG.Adapters.Behaviour
  def metadata do
    %{
      name: "Hakyll",
      language: "Haskell",
      description: "Haskell library for generating static sites",
      config_files: ["site.hs", "*.cabal"],
      template_dirs: ["templates/"]
    }
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:build, project_path, _opts}, _from, state) do
    Logger.info("Building Hakyll site at #{project_path}")

    site_bin = Path.join(project_path, "site")

    result =
      with true <- File.exists?(site_bin),
           {output, 0} <- System.cmd(site_bin, ["build"], cd: project_path, stderr_to_stdout: true) do
        {:ok, %{success: true, output: output}}
      else
        false ->
          {:error, "site binary not found. Run 'cabal build' first."}

        {error, code} ->
          {:error, "Build failed (exit #{code}): #{error}"}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:watch, project_path}, _from, state) do
    Logger.info("Starting Hakyll watch server at #{project_path}")

    site_bin = Path.join(project_path, "site")

    port_obj = Port.open(
      {:spawn_executable, site_bin},
      [:binary, :exit_status, args: ["watch"], cd: project_path]
    )

    # Hakyll watch typically uses port 8000
    {:reply, {:ok, 8000}, Map.put(state, :watch_port, port_obj)}
  end
end
