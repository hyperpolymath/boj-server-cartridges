# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolySSG.Adapters.Behaviour do
  @moduledoc """
  Behaviour defining the contract for SSG adapters.

  Each adapter implements this behaviour to provide a consistent interface
  for detecting, building, and managing static site generators.

  ## Example

      defmodule PolySSG.Adapters.Zola do
        use GenServer
        @behaviour PolySSG.Adapters.Behaviour

        @impl true
        def detect(project_path) do
          config_exists = File.exists?(Path.join(project_path, "config.toml"))
          {:ok, config_exists}
        end

        @impl true
        def build(project_path, opts) do
          # Run zola build command
        end
      end
  """

  @type project_path :: String.t()
  @type build_opts :: keyword()
  @type build_result :: {:ok, map()} | {:error, String.t()}
  @type detect_result :: {:ok, boolean()} | {:error, String.t()}

  @doc """
  Detect if this SSG is present in the project directory.

  Returns `{:ok, true}` if the SSG's config file exists, `{:ok, false}` otherwise.
  """
  @callback detect(project_path) :: detect_result

  @doc """
  Build the static site.

  ## Options

  - `:mode` - Build mode (`:dev`, `:prod`, `:draft`)
  - `:output_dir` - Override default output directory
  - `:base_url` - Override base URL
  """
  @callback build(project_path, build_opts) :: build_result

  @doc """
  Start the development server.

  Returns `{:ok, port}` with the port number the server is listening on.
  """
  @callback serve(project_path, build_opts) :: {:ok, pos_integer()} | {:error, String.t()}

  @doc """
  Clean build artifacts.
  """
  @callback clean(project_path) :: :ok | {:error, String.t()}

  @doc """
  Get SSG version.
  """
  @callback version() :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Get SSG metadata (name, language, description).
  """
  @callback metadata() :: %{
              name: String.t(),
              language: String.t(),
              description: String.t(),
              config_files: [String.t()],
              template_dirs: [String.t()]
            }
end
