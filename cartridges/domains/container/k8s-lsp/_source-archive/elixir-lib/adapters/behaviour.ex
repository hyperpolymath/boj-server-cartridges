# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyK8s.Adapters.Behaviour do
  @moduledoc """
  Behaviour defining the contract for Kubernetes orchestration tool adapters.

  Each adapter implements this behaviour to provide a consistent interface
  for detecting, applying, and managing Kubernetes resources via kubectl,
  Helm, Kustomize, and other K8s tools.

  ## Example

      defmodule PolyK8s.Adapters.Kubectl do
        use GenServer
        @behaviour PolyK8s.Adapters.Behaviour

        @impl true
        def detect(project_path) do
          manifests_exist = File.exists?(Path.join(project_path, "k8s"))
          {:ok, manifests_exist}
        end

        @impl true
        def apply(project_path, opts) do
          # Run kubectl apply command
        end
      end
  """

  @type project_path :: String.t()
  @type opts :: keyword()
  @type result :: {:ok, map()} | {:error, String.t()}
  @type detect_result :: {:ok, boolean()} | {:error, String.t()}

  @doc """
  Detect if this K8s tool is applicable to the project directory.

  Returns `{:ok, true}` if the tool's config/manifest files exist, `{:ok, false}` otherwise.
  """
  @callback detect(project_path) :: detect_result

  @doc """
  Apply Kubernetes resources to the cluster.

  ## Options

  - `:namespace` - Target namespace (default: "default")
  - `:context` - Kubectl context to use
  - `:dry_run` - Perform a dry run (`:client`, `:server`, or `false`)
  - `:force` - Force apply even if resources exist
  """
  @callback apply(project_path, opts) :: result

  @doc """
  Get Kubernetes resources from the cluster.

  ## Options

  - `:namespace` - Target namespace
  - `:resource_type` - Type of resource (e.g., "pods", "deployments")
  - `:selector` - Label selector
  - `:all_namespaces` - Get resources from all namespaces
  """
  @callback get_resources(project_path, opts) :: result

  @doc """
  Describe a specific Kubernetes resource.

  ## Options

  - `:namespace` - Target namespace
  - `:resource_type` - Type of resource (required)
  - `:name` - Resource name (required)
  """
  @callback describe(project_path, opts) :: result

  @doc """
  Get logs from a pod.

  ## Options

  - `:namespace` - Target namespace
  - `:pod` - Pod name (required)
  - `:container` - Container name (optional)
  - `:follow` - Follow log output
  - `:tail` - Number of lines to show
  """
  @callback logs(project_path, opts) :: result

  @doc """
  Perform rollout operations (status, restart, undo).

  ## Options

  - `:namespace` - Target namespace
  - `:resource` - Resource name (e.g., "deployment/my-app")
  - `:operation` - Operation type (`:status`, `:restart`, `:undo`)
  """
  @callback rollout(project_path, opts) :: result

  @doc """
  Get tool version.
  """
  @callback version() :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Get tool metadata (name, description, config patterns).
  """
  @callback metadata() :: %{
              name: String.t(),
              description: String.t(),
              config_files: [String.t()],
              manifest_patterns: [String.t()]
            }
end
