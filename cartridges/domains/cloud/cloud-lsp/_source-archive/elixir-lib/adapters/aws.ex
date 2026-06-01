# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyCloud.Adapters.AWS do
  @moduledoc """
  Adapter for Amazon Web Services (AWS) - Cloud computing platform.

  ## Configuration

  AWS uses credentials stored in `~/.aws/credentials` and config in `~/.aws/config`.
  Project-specific configuration can be in:
  - `cloudformation.yaml` / `cloudformation.json` - CloudFormation templates
  - `serverless.yml` - Serverless Framework
  - `cdk.json` - AWS CDK projects

  ## Commands

  - `aws cloudformation deploy` - Deploy CloudFormation stack
  - `aws cloudformation describe-stacks` - Get stack status
  - `aws logs tail` - Fetch CloudWatch logs
  - `aws configure` - Configure credentials
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
    cloudformation_yaml = Path.join(project_path, "cloudformation.yaml")
    cloudformation_json = Path.join(project_path, "cloudformation.json")
    serverless_yml = Path.join(project_path, "serverless.yml")
    cdk_json = Path.join(project_path, "cdk.json")

    detected =
      File.exists?(cloudformation_yaml) or
        File.exists?(cloudformation_json) or
        File.exists?(serverless_yml) or
        File.exists?(cdk_json)

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
    case System.cmd("aws", ["--version"], stderr_to_stdout: true) do
      {output, 0} ->
        version = output |> String.trim() |> String.split() |> List.first() |> String.replace("aws-cli/", "")
        {:ok, version}

      {error, _} ->
        {:error, error}
    end
  end

  @impl PolyCloud.Adapters.Behaviour
  def metadata do
    %{
      name: "AWS",
      cli_tool: "aws-cli",
      description: "Amazon Web Services cloud platform",
      config_files: ["cloudformation.yaml", "cloudformation.json", "serverless.yml", "cdk.json"],
      regions: ["us-east-1", "us-west-2", "eu-west-1", "ap-southeast-1"]
    }
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %{deployments: %{}, logs: %{}}}
  end

  @impl true
  def handle_call({:deploy, project_path, opts}, _from, state) do
    Logger.info("Deploying AWS resources at #{project_path}")

    stack_name = opts[:stack_name] || "poly-cloud-stack"
    region = opts[:region] || "us-east-1"
    template = opts[:template] || "cloudformation.yaml"

    args = [
      "cloudformation",
      "deploy",
      "--stack-name",
      stack_name,
      "--template-file",
      template,
      "--region",
      region
    ]

    args = if opts[:dry_run], do: args ++ ["--no-execute-changeset"], else: args

    case System.cmd("aws", args, cd: project_path, stderr_to_stdout: true) do
      {output, 0} ->
        result = %{
          success: true,
          stack_name: stack_name,
          region: region,
          output: output
        }

        {:reply, {:ok, result}, state}

      {error, exit_code} ->
        {:reply, {:error, "Deployment failed (exit #{exit_code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:configure, _project_path, opts}, _from, state) do
    region = opts[:region]
    profile = opts[:profile] || "default"

    args = ["configure", "set", "region", region, "--profile", profile]

    case System.cmd("aws", args, stderr_to_stdout: true) do
      {output, 0} ->
        {:reply, {:ok, %{region: region, profile: profile, output: output}}, state}

      {error, _} ->
        {:reply, {:error, error}, state}
    end
  end

  @impl true
  def handle_call({:status, _project_path, opts}, _from, state) do
    stack_name = opts[:stack_name] || "poly-cloud-stack"
    region = opts[:region] || "us-east-1"

    args = [
      "cloudformation",
      "describe-stacks",
      "--stack-name",
      stack_name,
      "--region",
      region,
      "--output",
      "json"
    ]

    case System.cmd("aws", args, stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, data} ->
            {:reply, {:ok, data}, state}

          {:error, _} ->
            {:reply, {:ok, %{raw: output}}, state}
        end

      {error, _} ->
        {:reply, {:error, error}, state}
    end
  end

  @impl true
  def handle_call({:logs, _project_path, opts}, _from, state) do
    log_group = opts[:service] || "/aws/cloudformation"
    since = opts[:since] || "1h"

    args = ["logs", "tail", log_group, "--since", since]
    args = if opts[:filter], do: args ++ ["--filter-pattern", opts[:filter]], else: args

    case System.cmd("aws", args, stderr_to_stdout: true) do
      {output, 0} ->
        logs = String.split(output, "\n", trim: true)
        {:reply, {:ok, logs}, state}

      {error, _} ->
        {:reply, {:error, error}, state}
    end
  end
end
