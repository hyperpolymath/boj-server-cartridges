# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyIaC.Adapters.Behaviour do
  @moduledoc """
  Behaviour defining the contract for IaC tool adapters.

  Each adapter implements this behaviour to provide a consistent interface
  for detecting, initializing, planning, and applying infrastructure changes.

  ## Example

      defmodule PolyIaC.Adapters.OpenTofu do
        use GenServer
        @behaviour PolyIaC.Adapters.Behaviour

        @impl true
        def detect(project_path) do
          config_exists = File.exists?(Path.join(project_path, "main.tf"))
          {:ok, config_exists}
        end

        @impl true
        def init(project_path, opts) do
          # Run tofu init command
        end
      end
  """

  @type project_path :: String.t()
  @type opts :: keyword()
  @type result :: {:ok, map()} | {:error, String.t()}
  @type detect_result :: {:ok, boolean()} | {:error, String.t()}

  @doc """
  Detect if this IaC tool is present in the project directory.

  Returns `{:ok, true}` if the tool's config files exist, `{:ok, false}` otherwise.
  """
  @callback detect(project_path) :: detect_result

  @doc """
  Initialize the IaC project (downloads providers, modules, etc.).

  ## Options

  - `:backend_config` - Backend configuration overrides
  - `:upgrade` - Upgrade providers to latest versions
  - `:reconfigure` - Reconfigure backend
  """
  @callback init(project_path, opts) :: result

  @doc """
  Generate and show an execution plan.

  ## Options

  - `:var_file` - Path to variable file
  - `:vars` - Map of variable overrides
  - `:target` - Limit planning to specific resources
  - `:destroy` - Create a plan to destroy all resources
  - `:out` - Write plan to file
  """
  @callback plan(project_path, opts) :: result

  @doc """
  Apply the changes required to reach the desired state.

  ## Options

  - `:var_file` - Path to variable file
  - `:vars` - Map of variable overrides
  - `:target` - Limit apply to specific resources
  - `:auto_approve` - Skip interactive approval (use with caution)
  - `:plan_file` - Apply a saved plan file
  """
  @callback apply(project_path, opts) :: result

  @doc """
  Destroy infrastructure managed by this configuration.

  ## Options

  - `:var_file` - Path to variable file
  - `:vars` - Map of variable overrides
  - `:target` - Limit destruction to specific resources
  - `:auto_approve` - Skip interactive approval (use with caution)
  """
  @callback destroy(project_path, opts) :: result

  @doc """
  Validate the configuration files.

  Returns `{:ok, result}` with validation details or `{:error, reason}`.
  """
  @callback validate(project_path) :: result

  @doc """
  Get IaC tool version.
  """
  @callback version() :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Get IaC tool metadata (name, language, description).
  """
  @callback metadata() :: %{
              name: String.t(),
              language: String.t(),
              description: String.t(),
              config_files: [String.t()],
              state_files: [String.t()],
              foss_first: boolean()
            }
end
