# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyCloud.Adapters.GCP do
  @moduledoc """
  Adapter for Google Cloud Platform (GCP) - Google's cloud computing platform.

  ## Configuration

  GCP uses credentials managed by `gcloud auth` and config stored in `~/.config/gcloud/`.
  Project-specific configuration can be in:
  - `app.yaml` - App Engine config
  - `cloudbuild.yaml` - Cloud Build config
  - `deployment-manager.yaml` - Deployment Manager templates

  ## Commands

  - `gcloud app deploy` - Deploy to App Engine
  - `gcloud deployment-manager deployments create` - Create deployment
  - `gcloud deployment-manager deployments describe` - Get deployment status
  - `gcloud logging read` - Fetch logs
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
    app_yaml = Path.join(project_path, "app.yaml")
    cloudbuild_yaml = Path.join(project_path, "cloudbuild.yaml")
    deployment_yaml = Path.join(project_path, "deployment-manager.yaml")

    detected =
      File.exists?(app_yaml) or
        File.exists?(cloudbuild_yaml) or
        File.exists?(deployment_yaml)

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
    case System.cmd("gcloud", ["version"], stderr_to_stdout: true) do
      {output, 0} ->
        version =
          output
          |> String.split("\n")
          |> List.first()
          |> String.replace("Google Cloud SDK ", "")
          |> String.trim()

        {:ok, version}

      {error, _} ->
        {:error, error}
    end
  end

  @impl PolyCloud.Adapters.Behaviour
  def metadata do
    %{
      name: "GCP",
      cli_tool: "gcloud",
      description: "Google Cloud Platform",
      config_files: ["app.yaml", "cloudbuild.yaml", "deployment-manager.yaml"],
      regions: ["us-central1", "us-east1", "europe-west1", "asia-southeast1"]
    }
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %{deployments: %{}, logs: %{}}}
  end

  @impl true
  def handle_call({:deploy, project_path, opts}, _from, state) do
    Logger.info("Deploying GCP resources at #{project_path}")

    deployment_type = opts[:type] || :app_engine
    project_id = opts[:project_id]

    args =
      case deployment_type do
        :app_engine ->
          base = ["app", "deploy", "app.yaml", "--quiet"]
          if project_id, do: base ++ ["--project", project_id], else: base

        :deployment_manager ->
          deployment_name = opts[:deployment_name] || "poly-cloud-deployment"
          config = opts[:config] || "deployment-manager.yaml"

          base = [
            "deployment-manager",
            "deployments",
            "create",
            deployment_name,
            "--config",
            config
          ]

          if project_id, do: base ++ ["--project", project_id], else: base
      end

    case System.cmd("gcloud", args, cd: project_path, stderr_to_stdout: true) do
      {output, 0} ->
        result = %{
          success: true,
          deployment_type: deployment_type,
          project_id: project_id,
          output: output
        }

        {:reply, {:ok, result}, state}

      {error, exit_code} ->
        {:reply, {:error, "Deployment failed (exit #{exit_code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:configure, _project_path, opts}, _from, state) do
    project_id = opts[:project_id]
    region = opts[:region]

    results = []

    results =
      if project_id do
        case System.cmd("gcloud", ["config", "set", "project", project_id],
               stderr_to_stdout: true
             ) do
          {_, 0} -> [{:project, project_id} | results]
          _ -> results
        end
      else
        results
      end

    results =
      if region do
        case System.cmd("gcloud", ["config", "set", "compute/region", region],
               stderr_to_stdout: true
             ) do
          {_, 0} -> [{:region, region} | results]
          _ -> results
        end
      else
        results
      end

    {:reply, {:ok, Map.new(results)}, state}
  end

  @impl true
  def handle_call({:status, _project_path, opts}, _from, state) do
    deployment_name = opts[:deployment_name] || "poly-cloud-deployment"
    project_id = opts[:project_id]

    args = ["deployment-manager", "deployments", "describe", deployment_name, "--format", "json"]
    args = if project_id, do: args ++ ["--project", project_id], else: args

    case System.cmd("gcloud", args, stderr_to_stdout: true) do
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
    project_id = opts[:project_id]
    service = opts[:service]
    limit = opts[:limit] || 100

    filter =
      if service do
        "resource.type=\"#{service}\""
      else
        "severity>=DEFAULT"
      end

    args = ["logging", "read", filter, "--limit", to_string(limit), "--format", "value(textPayload)"]
    args = if project_id, do: args ++ ["--project", project_id], else: args

    case System.cmd("gcloud", args, stderr_to_stdout: true) do
      {output, 0} ->
        logs = String.split(output, "\n", trim: true)
        {:reply, {:ok, logs}, state}

      {error, _} ->
        {:reply, {:error, error}, state}
    end
  end
end
