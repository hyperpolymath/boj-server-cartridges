# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyCloud.Adapters.DigitalOcean do
  @moduledoc """
  Adapter for DigitalOcean - Developer-focused cloud platform.

  ## Configuration

  DigitalOcean uses credentials stored in `~/.config/doctl/config.yaml`.
  Project-specific configuration can be in:
  - `.do/app.yaml` - App Platform config
  - `kubernetes.yaml` - Kubernetes manifest
  - `docker-compose.yml` - Container definitions

  ## Commands

  - `doctl apps create` - Deploy to App Platform
  - `doctl apps get` - Get app status
  - `doctl apps logs` - Fetch app logs
  - `doctl kubernetes cluster create` - Create Kubernetes cluster
  """
  use GenServer
  @behaviour PolyCloud.Adapters.Behaviour

  require Logger

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl PolyCloud.Adapters.Behaviour
  def detect(project_path) do
    app_yaml = Path.join(project_path, ".do/app.yaml")
    k8s_yaml = Path.join(project_path, "kubernetes.yaml")
    docker_compose = Path.join(project_path, "docker-compose.yml")

    detected =
      File.exists?(app_yaml) or
        File.exists?(k8s_yaml) or
        File.exists?(docker_compose)

    {:ok, detected}
  end

  @impl PolyCloud.Adapters.Behaviour
  def deploy(project_path, opts) do
    GenServer.call(__MODULE__, {:deploy, project_path, opts})
  end

  @impl PolyCloud.Adapters.Behaviour
  def configure(project_path, opts) do
    GenServer.call(__MODULE__, {:configure, project_path, opts})
  end

  @impl PolyCloud.Adapters.Behaviour
  def status(project_path, opts) do
    GenServer.call(__MODULE__, {:status, project_path, opts})
  end

  @impl PolyCloud.Adapters.Behaviour
  def logs(project_path, opts) do
    GenServer.call(__MODULE__, {:logs, project_path, opts})
  end

  @impl PolyCloud.Adapters.Behaviour
  def version do
    case System.cmd("doctl", ["version"], stderr_to_stdout: true) do
      {output, 0} ->
        version =
          output
          |> String.split()
          |> Enum.find_value(fn part ->
            if String.starts_with?(part, "doctl"), do: String.replace(part, "doctl", "")
          end)
          |> String.trim()

        {:ok, version}

      {error, _} ->
        {:error, error}
    end
  end

  @impl PolyCloud.Adapters.Behaviour
  def metadata do
    %{
      name: "DigitalOcean",
      cli_tool: "doctl",
      description: "DigitalOcean cloud platform",
      config_files: [".do/app.yaml", "kubernetes.yaml", "docker-compose.yml"],
      regions: ["nyc1", "sfo2", "ams3", "sgp1", "lon1", "fra1"]
    }
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %{deployments: %{}, logs: %{}}}
  end

  @impl true
  def handle_call({:deploy, project_path, opts}, _from, state) do
    Logger.info("Deploying DigitalOcean resources at #{project_path}")

    deployment_type = opts[:type] || :app_platform
    app_spec = opts[:app_spec] || ".do/app.yaml"

    args =
      case deployment_type do
        :app_platform ->
          if File.exists?(Path.join(project_path, app_spec)) do
            ["apps", "create", "--spec", app_spec]
          else
            ["apps", "create", "--upsert"]
          end

        :kubernetes ->
          cluster_name = opts[:cluster_name] || "poly-cloud-cluster"
          region = opts[:region] || "nyc1"
          node_pool = opts[:node_pool] || "basic-nodes"

          [
            "kubernetes",
            "cluster",
            "create",
            cluster_name,
            "--region",
            region,
            "--node-pool",
            node_pool
          ]
      end

    case System.cmd("doctl", args, cd: project_path, stderr_to_stdout: true) do
      {output, 0} ->
        result = %{
          success: true,
          deployment_type: deployment_type,
          output: output
        }

        {:reply, {:ok, result}, state}

      {error, exit_code} ->
        {:reply, {:error, "Deployment failed (exit #{exit_code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:configure, _project_path, opts}, _from, state) do
    token = opts[:token]
    context = opts[:context]

    results = []

    results =
      if token do
        case System.cmd("doctl", ["auth", "init", "--access-token", token],
               stderr_to_stdout: true
             ) do
          {_, 0} -> [{:authenticated, true} | results]
          _ -> results
        end
      else
        results
      end

    results =
      if context do
        case System.cmd("doctl", ["auth", "switch", "--context", context],
               stderr_to_stdout: true
             ) do
          {_, 0} -> [{:context, context} | results]
          _ -> results
        end
      else
        results
      end

    {:reply, {:ok, Map.new(results)}, state}
  end

  @impl true
  def handle_call({:status, _project_path, opts}, _from, state) do
    app_id = opts[:app_id]

    if app_id do
      args = ["apps", "get", app_id, "--format", "json"]

      case System.cmd("doctl", args, stderr_to_stdout: true) do
        {output, 0} ->
          case Jason.decode(output) do
            {:ok, data} -> {:reply, {:ok, data}, state}
            {:error, _} -> {:reply, {:ok, %{raw: output}}, state}
          end

        {error, _} ->
          {:reply, {:error, error}, state}
      end
    else
      {:reply, {:error, "app_id required for status check"}, state}
    end
  end

  @impl true
  def handle_call({:logs, _project_path, opts}, _from, state) do
    app_id = opts[:app_id]
    component = opts[:component]
    tail = opts[:tail] || false

    if app_id do
      args = ["apps", "logs", app_id]
      args = if component, do: args ++ ["--component", component], else: args
      args = if tail, do: args ++ ["--follow"], else: args

      case System.cmd("doctl", args, stderr_to_stdout: true) do
        {output, 0} ->
          logs = String.split(output, "\n", trim: true)
          {:reply, {:ok, logs}, state}

        {error, _} ->
          {:reply, {:error, error}, state}
      end
    else
      {:reply, {:error, "app_id required for logs"}, state}
    end
  end
end
