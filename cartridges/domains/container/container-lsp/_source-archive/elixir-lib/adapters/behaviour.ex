# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyContainer.Adapters.Behaviour do
  @moduledoc """
  Behaviour defining the contract for container runtime adapters.

  Each adapter implements this behaviour to provide a consistent interface
  for detecting, running, building, and managing containers across different
  container runtimes (nerdctl, podman, docker).

  ## Example

      defmodule PolyContainer.Adapters.Nerdctl do
        use GenServer
        @behaviour PolyContainer.Adapters.Behaviour

        @impl true
        def detect do
          {:ok, System.find_executable("nerdctl") != nil}
        end

        @impl true
        def run(image, opts) do
          # Run container with nerdctl
        end
      end
  """

  @type image :: String.t()
  @type container_id :: String.t()
  @type run_opts :: keyword()
  @type build_opts :: keyword()
  @type result :: {:ok, map()} | {:error, String.t()}
  @type detect_result :: {:ok, boolean()} | {:error, String.t()}

  @doc """
  Detect if this container runtime is available on the system.

  Returns `{:ok, true}` if the runtime executable is found, `{:ok, false}` otherwise.
  """
  @callback detect() :: detect_result

  @doc """
  Run a container from an image.

  ## Options

  - `:name` - Container name
  - `:detach` - Run in background (default: true)
  - `:ports` - Port mappings (e.g., ["8080:80"])
  - `:env` - Environment variables (e.g., ["KEY=value"])
  - `:volumes` - Volume mounts (e.g., ["/host:/container"])
  - `:command` - Command to run in container
  - `:args` - Arguments to command
  - `:network` - Network to attach to
  - `:rm` - Remove container after exit
  """
  @callback run(image, run_opts) :: {:ok, container_id} | {:error, String.t()}

  @doc """
  Build a container image from a Dockerfile or Containerfile.

  ## Options

  - `:context` - Build context directory (default: ".")
  - `:dockerfile` - Dockerfile path (default: "Dockerfile")
  - `:tags` - Image tags (e.g., ["myapp:latest", "myapp:v1.0"])
  - `:build_args` - Build arguments
  - `:target` - Multi-stage build target
  - `:platform` - Target platform (e.g., "linux/amd64")
  """
  @callback build(build_opts) :: result

  @doc """
  Inspect a container and return detailed information.

  Returns container metadata including status, network, mounts, etc.
  """
  @callback inspect(container_id) :: result

  @doc """
  Get logs from a container.

  ## Options

  - `:follow` - Follow log output (stream)
  - `:tail` - Number of lines to show from end
  - `:since` - Show logs since timestamp
  - `:timestamps` - Show timestamps
  """
  @callback logs(container_id, keyword()) :: result

  @doc """
  Get container runtime version.

  Returns version string for the runtime (e.g., "nerdctl 1.7.0").
  """
  @callback version() :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Get container runtime metadata (name, implementation, features).

  ## Metadata fields

  - `:name` - Runtime name (e.g., "nerdctl")
  - `:implementation` - Implementation type (e.g., "containerd", "OCI")
  - `:description` - Brief description
  - `:features` - Supported features list
  - `:rootless` - Whether rootless mode is supported
  """
  @callback metadata() :: %{
              name: String.t(),
              implementation: String.t(),
              description: String.t(),
              features: [String.t()],
              rootless: boolean()
            }
end
