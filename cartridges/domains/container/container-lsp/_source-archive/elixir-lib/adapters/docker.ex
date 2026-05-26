# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyContainer.Adapters.Docker do
  @moduledoc """
  Adapter for Docker - Industry standard container platform.

  Docker is the original and most widely-used container platform, providing
  a complete ecosystem for building, shipping, and running containerized
  applications.

  ## Features

  - Industry standard
  - Docker Hub integration
  - Docker Compose
  - BuildKit
  - Multi-platform builds
  - Docker Desktop

  ## Commands

  - `docker run` - Run a container
  - `docker build` - Build an image
  - `docker inspect` - Inspect container/image
  - `docker logs` - View container logs
  - `docker compose` - Manage multi-container applications
  """
  use GenServer
  @behaviour PolyContainer.Adapters.Behaviour

  require Logger

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl PolyContainer.Adapters.Behaviour
  def detect do
    {:ok, System.find_executable("docker") != nil}
  end

  @impl PolyContainer.Adapters.Behaviour
  def run(image, opts) do
    GenServer.call(__MODULE__, {:run, image, opts}, 30_000)
  end

  @impl PolyContainer.Adapters.Behaviour
  def build(opts) do
    GenServer.call(__MODULE__, {:build, opts}, 300_000)
  end

  @impl PolyContainer.Adapters.Behaviour
  def inspect(container_id) do
    GenServer.call(__MODULE__, {:inspect, container_id})
  end

  @impl PolyContainer.Adapters.Behaviour
  def logs(container_id, opts) do
    GenServer.call(__MODULE__, {:logs, container_id, opts})
  end

  @impl PolyContainer.Adapters.Behaviour
  def version do
    case System.cmd("docker", ["--version"], stderr_to_stdout: true) do
      {output, 0} ->
        version = output |> String.trim() |> String.replace("Docker version ", "")
        {:ok, version}

      {error, _} ->
        {:error, error}
    end
  end

  @impl PolyContainer.Adapters.Behaviour
  def metadata do
    %{
      name: "docker",
      implementation: "docker-engine",
      description: "Industry standard container platform with comprehensive ecosystem",
      features: [
        "docker-hub",
        "compose",
        "buildkit",
        "multi-platform",
        "swarm",
        "desktop"
      ],
      rootless: false
    }
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %{containers: %{}, builds: %{}}}
  end

  @impl true
  def handle_call({:run, image, opts}, _from, state) do
    Logger.info("Running container from image #{image} with docker")

    args = ["run"]
    args = if opts[:detach], do: args ++ ["-d"], else: args
    args = if opts[:name], do: args ++ ["--name", opts[:name]], else: args
    args = if opts[:rm], do: args ++ ["--rm"], else: args

    # Add port mappings
    args =
      Enum.reduce(opts[:ports] || [], args, fn port, acc ->
        acc ++ ["-p", port]
      end)

    # Add environment variables
    args =
      Enum.reduce(opts[:env] || [], args, fn env, acc ->
        acc ++ ["-e", env]
      end)

    # Add volume mounts
    args =
      Enum.reduce(opts[:volumes] || [], args, fn vol, acc ->
        acc ++ ["-v", vol]
      end)

    # Add network
    args = if opts[:network], do: args ++ ["--network", opts[:network]], else: args

    # Add image and command
    args = args ++ [image]
    args = if opts[:command], do: args ++ [opts[:command] | opts[:args] || []], else: args

    case System.cmd("docker", args, stderr_to_stdout: true) do
      {output, 0} ->
        container_id = String.trim(output)
        {:reply, {:ok, container_id}, state}

      {error, exit_code} ->
        {:reply, {:error, "Run failed (exit #{exit_code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:build, opts}, _from, state) do
    Logger.info("Building image with docker")

    context = opts[:context] || "."
    args = ["build"]

    args = if opts[:dockerfile], do: args ++ ["-f", opts[:dockerfile]], else: args
    args = if opts[:target], do: args ++ ["--target", opts[:target]], else: args
    args = if opts[:platform], do: args ++ ["--platform", opts[:platform]], else: args

    # Add tags
    args =
      Enum.reduce(opts[:tags] || [], args, fn tag, acc ->
        acc ++ ["-t", tag]
      end)

    # Add build args
    args =
      Enum.reduce(opts[:build_args] || [], args, fn {key, val}, acc ->
        acc ++ ["--build-arg", "#{key}=#{val}"]
      end)

    args = args ++ [context]

    case System.cmd("docker", args, stderr_to_stdout: true) do
      {output, 0} ->
        result = %{
          success: true,
          output: output
        }

        {:reply, {:ok, result}, state}

      {error, exit_code} ->
        {:reply, {:error, "Build failed (exit #{exit_code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:inspect, container_id}, _from, state) do
    case System.cmd("docker", ["inspect", container_id], stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, data} -> {:reply, {:ok, data}, state}
          {:error, _} -> {:reply, {:error, "Failed to parse inspect output"}, state}
        end

      {error, exit_code} ->
        {:reply, {:error, "Inspect failed (exit #{exit_code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:logs, container_id, opts}, _from, state) do
    args = ["logs"]
    args = if opts[:follow], do: args ++ ["-f"], else: args
    args = if opts[:tail], do: args ++ ["--tail", to_string(opts[:tail])], else: args
    args = if opts[:since], do: args ++ ["--since", opts[:since]], else: args
    args = if opts[:timestamps], do: args ++ ["-t"], else: args
    args = args ++ [container_id]

    case System.cmd("docker", args, stderr_to_stdout: true) do
      {output, 0} ->
        {:reply, {:ok, %{logs: output}}, state}

      {error, exit_code} ->
        {:reply, {:error, "Logs failed (exit #{exit_code}): #{error}"}, state}
    end
  end
end
