# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyContainer.Adapters.Nerdctl do
  @moduledoc """
  Adapter for nerdctl - Docker-compatible CLI for containerd.

  nerdctl is a Docker-compatible CLI for containerd with support for
  Compose, rootless mode, image encryption, lazy-pulling, and more.

  ## Features

  - Docker-compatible CLI
  - Native support for containerd
  - Rootless mode
  - Image encryption and signing
  - Lazy pulling (stargz)
  - IPFS integration

  ## Commands

  - `nerdctl run` - Run a container
  - `nerdctl build` - Build an image
  - `nerdctl inspect` - Inspect container/image
  - `nerdctl logs` - View container logs
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
    {:ok, System.find_executable("nerdctl") != nil}
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
    case System.cmd("nerdctl", ["--version"], stderr_to_stdout: true) do
      {output, 0} ->
        version = output |> String.trim() |> String.replace("nerdctl version ", "")
        {:ok, version}

      {error, _} ->
        {:error, error}
    end
  end

  @impl PolyContainer.Adapters.Behaviour
  def metadata do
    %{
      name: "nerdctl",
      implementation: "containerd",
      description: "Docker-compatible CLI for containerd with enhanced features",
      features: [
        "docker-compatible",
        "rootless",
        "image-encryption",
        "lazy-pulling",
        "ipfs",
        "compose",
        "buildkit"
      ],
      rootless: true
    }
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %{containers: %{}, builds: %{}}}
  end

  @impl true
  def handle_call({:run, image, opts}, _from, state) do
    Logger.info("Running container from image #{image} with nerdctl")

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

    case System.cmd("nerdctl", args, stderr_to_stdout: true) do
      {output, 0} ->
        container_id = String.trim(output)
        {:reply, {:ok, container_id}, state}

      {error, exit_code} ->
        {:reply, {:error, "Run failed (exit #{exit_code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:build, opts}, _from, state) do
    Logger.info("Building image with nerdctl")

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

    case System.cmd("nerdctl", args, stderr_to_stdout: true) do
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
    case System.cmd("nerdctl", ["inspect", container_id], stderr_to_stdout: true) do
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

    case System.cmd("nerdctl", args, stderr_to_stdout: true) do
      {output, 0} ->
        {:reply, {:ok, %{logs: output}}, state}

      {error, exit_code} ->
        {:reply, {:error, "Logs failed (exit #{exit_code}): #{error}"}, state}
    end
  end
end
