# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyCloud.Adapters.Azure do
  @moduledoc """
  Adapter for Microsoft Azure - Microsoft's cloud computing platform.

  ## Configuration

  Azure uses credentials managed by `az login` and config stored in `~/.azure/`.
  Project-specific configuration can be in:
  - `azuredeploy.json` - ARM template
  - `azuredeploy.parameters.json` - ARM parameters
  - `azure-pipelines.yml` - Azure DevOps pipelines

  ## Commands

  - `az deployment group create` - Deploy ARM template
  - `az deployment group show` - Get deployment status
  - `az monitor log-analytics query` - Query logs
  - `az configure` - Configure settings
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
    arm_template = Path.join(project_path, "azuredeploy.json")
    arm_params = Path.join(project_path, "azuredeploy.parameters.json")
    pipelines = Path.join(project_path, "azure-pipelines.yml")

    detected =
      File.exists?(arm_template) or
        File.exists?(arm_params) or
        File.exists?(pipelines)

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
    case System.cmd("az", ["version"], stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, %{"azure-cli" => version}} ->
            {:ok, version}

          _ ->
            {:ok, String.trim(output)}
        end

      {error, _} ->
        {:error, error}
    end
  end

  @impl PolyCloud.Adapters.Behaviour
  def metadata do
    %{
      name: "Azure",
      cli_tool: "az",
      description: "Microsoft Azure cloud platform",
      config_files: ["azuredeploy.json", "azuredeploy.parameters.json", "azure-pipelines.yml"],
      regions: ["eastus", "westus", "westeurope", "southeastasia"]
    }
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %{deployments: %{}, logs: %{}}}
  end

  @impl true
  def handle_call({:deploy, project_path, opts}, _from, state) do
    Logger.info("Deploying Azure resources at #{project_path}")

    resource_group = opts[:resource_group] || "poly-cloud-rg"
    deployment_name = opts[:deployment_name] || "poly-cloud-deployment"
    template = opts[:template] || "azuredeploy.json"
    parameters = opts[:parameters] || "azuredeploy.parameters.json"

    args = [
      "deployment",
      "group",
      "create",
      "--resource-group",
      resource_group,
      "--name",
      deployment_name,
      "--template-file",
      template
    ]

    args =
      if File.exists?(Path.join(project_path, parameters)) do
        args ++ ["--parameters", parameters]
      else
        args
      end

    args = if opts[:dry_run], do: args ++ ["--what-if"], else: args

    case System.cmd("az", args, cd: project_path, stderr_to_stdout: true) do
      {output, 0} ->
        result = %{
          success: true,
          resource_group: resource_group,
          deployment_name: deployment_name,
          output: output
        }

        {:reply, {:ok, result}, state}

      {error, exit_code} ->
        {:reply, {:error, "Deployment failed (exit #{exit_code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:configure, _project_path, opts}, _from, state) do
    location = opts[:location]
    defaults = opts[:defaults] || []

    results = []

    results =
      if location do
        case System.cmd("az", ["configure", "--defaults", "location=#{location}"],
               stderr_to_stdout: true
             ) do
          {_, 0} -> [{:location, location} | results]
          _ -> results
        end
      else
        results
      end

    results =
      Enum.reduce(defaults, results, fn {key, value}, acc ->
        case System.cmd("az", ["configure", "--defaults", "#{key}=#{value}"],
               stderr_to_stdout: true
             ) do
          {_, 0} -> [{key, value} | acc]
          _ -> acc
        end
      end)

    {:reply, {:ok, Map.new(results)}, state}
  end

  @impl true
  def handle_call({:status, _project_path, opts}, _from, state) do
    resource_group = opts[:resource_group] || "poly-cloud-rg"
    deployment_name = opts[:deployment_name] || "poly-cloud-deployment"

    args = [
      "deployment",
      "group",
      "show",
      "--resource-group",
      resource_group,
      "--name",
      deployment_name,
      "--output",
      "json"
    ]

    case System.cmd("az", args, stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, data} -> {:reply, {:ok, data}, state}
          {:error, _} -> {:reply, {:ok, %{raw: output}}, state}
        end

      {error, _} ->
        {:reply, {:error, error}, state}
    end
  end

  @impl true
  def handle_call({:logs, _project_path, opts}, _from, state) do
    workspace_id = opts[:workspace_id]
    query = opts[:query] || "AzureActivity | limit 100"
    timespan = opts[:since] || "PT1H"

    if workspace_id do
      args = [
        "monitor",
        "log-analytics",
        "query",
        "--workspace",
        workspace_id,
        "--analytics-query",
        query,
        "--timespan",
        timespan
      ]

      case System.cmd("az", args, stderr_to_stdout: true) do
        {output, 0} ->
          case Jason.decode(output) do
            {:ok, data} ->
              logs =
                data
                |> Map.get("tables", [])
                |> List.first()
                |> Map.get("rows", [])
                |> Enum.map(&to_string/1)

              {:reply, {:ok, logs}, state}

            {:error, _} ->
              {:reply, {:ok, [output]}, state}
          end

        {error, _} ->
          {:reply, {:error, error}, state}
      end
    else
      {:reply, {:error, "workspace_id required for Azure logs"}, state}
    end
  end
end
