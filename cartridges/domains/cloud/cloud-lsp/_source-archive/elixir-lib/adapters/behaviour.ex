# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyCloud.Adapters.Behaviour do
  @moduledoc """
  Behaviour defining the contract for cloud provider adapters.

  Each adapter implements this behaviour to provide a consistent interface
  for detecting, deploying, and managing cloud resources across AWS, GCP,
  Azure, DigitalOcean, and other providers.

  ## Example

      defmodule PolyCloud.Adapters.AWS do
        use GenServer
        @behaviour PolyCloud.Adapters.Behaviour

        @impl true
        def detect(project_path) do
          # Check for AWS CLI, credentials, or CloudFormation templates
          {:ok, aws_detected?}
        end

        @impl true
        def deploy(project_path, opts) do
          # Run deployment command
        end
      end
  """

  @type project_path :: String.t()
  @type deploy_opts :: keyword()
  @type deploy_result :: {:ok, map()} | {:error, String.t()}
  @type detect_result :: {:ok, boolean()} | {:error, String.t()}
  @type status_result :: {:ok, map()} | {:error, String.t()}
  @type logs_result :: {:ok, [String.t()]} | {:error, String.t()}

  @doc """
  Detect if this cloud provider is configured in the project directory.

  Returns `{:ok, true}` if provider config/credentials exist, `{:ok, false}` otherwise.
  """
  @callback detect(project_path) :: detect_result

  @doc """
  Deploy resources to the cloud provider.

  ## Options

  - `:environment` - Target environment (`:dev`, `:staging`, `:prod`)
  - `:region` - Cloud region/zone
  - `:dry_run` - Simulate deployment without executing
  - `:stack_name` - Stack/deployment identifier
  """
  @callback deploy(project_path, deploy_opts) :: deploy_result

  @doc """
  Configure cloud provider settings.

  ## Options

  - `:region` - Set default region
  - `:profile` - Set credential profile
  - `:credentials` - Update credentials (handled securely)
  """
  @callback configure(project_path, deploy_opts) :: {:ok, map()} | {:error, String.t()}

  @doc """
  Get deployment status for resources.

  Returns status information including:
  - Active resources
  - Health checks
  - Cost estimates (if available)
  - Last deployment timestamp
  """
  @callback status(project_path, deploy_opts) :: status_result

  @doc """
  Fetch logs from deployed resources.

  ## Options

  - `:service` - Service/resource to fetch logs from
  - `:since` - Time range (e.g., "1h", "24h")
  - `:tail` - Follow logs in real-time
  - `:filter` - Log filter pattern
  """
  @callback logs(project_path, deploy_opts) :: logs_result

  @doc """
  Get cloud provider CLI version.
  """
  @callback version() :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Get cloud provider metadata (name, CLI tool, description).
  """
  @callback metadata() :: %{
              name: String.t(),
              cli_tool: String.t(),
              description: String.t(),
              config_files: [String.t()],
              regions: [String.t()]
            }
end
