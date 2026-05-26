# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyIaC.Adapters.Pulumi do
  @moduledoc """
  Adapter for Pulumi - Modern IaC using real programming languages.

  ## Configuration

  Pulumi uses `Pulumi.yaml` at the project root with language-specific code:
  - `Pulumi.yaml` - Project configuration
  - `Pulumi.<stack>.yaml` - Stack-specific configuration
  - Source files in TypeScript, Python, Go, .NET, Java, or YAML

  ## Commands

  - `pulumi preview` - Preview changes (equivalent to plan)
  - `pulumi up` - Create or update resources
  - `pulumi destroy` - Destroy all resources
  - `pulumi refresh` - Refresh state from actual infrastructure
  - `pulumi stack` - Manage stacks

  ## FOSS Status

  Pulumi is open source (Apache-2.0) but requires a backend (Pulumi Cloud or self-hosted).
  For fully FOSS deployments, OpenTofu is preferred per FOSS-first policy.
  """
  use GenServer
  @behaviour PolyIaC.Adapters.Behaviour

  require Logger

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl PolyIaC.Adapters.Behaviour
  def detect(project_path) do
    pulumi_yaml = Path.join(project_path, "Pulumi.yaml")
    {:ok, File.exists?(pulumi_yaml)}
  end

  @impl PolyIaC.Adapters.Behaviour
  def init(project_path, opts) do
    GenServer.call(__MODULE__, {:init, project_path, opts}, :infinity)
  end

  @impl PolyIaC.Adapters.Behaviour
  def plan(project_path, opts) do
    # Pulumi calls this "preview"
    GenServer.call(__MODULE__, {:preview, project_path, opts}, :infinity)
  end

  @impl PolyIaC.Adapters.Behaviour
  def apply(project_path, opts) do
    # Pulumi calls this "up"
    GenServer.call(__MODULE__, {:up, project_path, opts}, :infinity)
  end

  @impl PolyIaC.Adapters.Behaviour
  def destroy(project_path, opts) do
    GenServer.call(__MODULE__, {:destroy, project_path, opts}, :infinity)
  end

  @impl PolyIaC.Adapters.Behaviour
  def validate(project_path) do
    # Pulumi doesn't have a separate validate command, use preview --dry-run
    GenServer.call(__MODULE__, {:validate, project_path}, :infinity)
  end

  @impl PolyIaC.Adapters.Behaviour
  def version do
    case System.cmd("pulumi", ["version"], stderr_to_stdout: true) do
      {output, 0} ->
        version =
          output
          |> String.trim()
          |> String.replace("v", "")

        {:ok, version}

      {error, _} ->
        {:error, error}
    end
  end

  @impl PolyIaC.Adapters.Behaviour
  def metadata do
    %{
      name: "Pulumi",
      language: "Multi-language (TypeScript, Python, Go, .NET, Java, YAML)",
      description: "Modern IaC using real programming languages (Apache-2.0)",
      config_files: ["Pulumi.yaml", "Pulumi.*.yaml"],
      state_files: [".pulumi/"],
      foss_first: false
    }
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %{operations: %{}}}
  end

  @impl true
  def handle_call({:init, project_path, opts}, _from, state) do
    Logger.info("Initializing Pulumi project at #{project_path}")

    # Pulumi init is only for new projects, for existing projects we just verify
    case File.exists?(Path.join(project_path, "Pulumi.yaml")) do
      true ->
        # Project already initialized, return success
        result = %{
          success: true,
          output: "Pulumi project already initialized"
        }

        {:reply, {:ok, result}, state}

      false ->
        {:reply, {:error, "Pulumi.yaml not found. Use 'pulumi new' to create a new project."},
         state}
    end
  end

  @impl true
  def handle_call({:preview, project_path, opts}, _from, state) do
    Logger.info("Previewing Pulumi changes at #{project_path}")

    args = ["preview", "--non-interactive", "--json"]

    args =
      if opts[:stack] do
        args ++ ["--stack", opts[:stack]]
      else
        args
      end

    args =
      if opts[:config] do
        Enum.reduce(opts[:config], args, fn {key, value}, acc ->
          acc ++ ["--config", "#{key}=#{value}"]
        end)
      else
        args
      end

    case System.cmd("pulumi", args, cd: project_path, stderr_to_stdout: true) do
      {output, 0} ->
        result = %{
          success: true,
          output: output,
          changes_detected: String.contains?(output, "\"changes\"")
        }

        {:reply, {:ok, result}, state}

      {error, exit_code} ->
        {:reply, {:error, "Preview failed (exit #{exit_code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:up, project_path, opts}, _from, state) do
    Logger.info("Applying Pulumi changes at #{project_path}")

    args = ["up", "--non-interactive"]
    args = if opts[:yes], do: args ++ ["--yes"], else: args

    args =
      if opts[:stack] do
        args ++ ["--stack", opts[:stack]]
      else
        args
      end

    args =
      if opts[:config] do
        Enum.reduce(opts[:config], args, fn {key, value}, acc ->
          acc ++ ["--config", "#{key}=#{value}"]
        end)
      else
        args
      end

    args =
      if opts[:target] do
        List.wrap(opts[:target])
        |> Enum.reduce(args, fn target, acc ->
          acc ++ ["--target", target]
        end)
      else
        args
      end

    case System.cmd("pulumi", args, cd: project_path, stderr_to_stdout: true) do
      {output, 0} ->
        result = %{
          success: true,
          output: output
        }

        {:reply, {:ok, result}, state}

      {error, exit_code} ->
        {:reply, {:error, "Up failed (exit #{exit_code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:destroy, project_path, opts}, _from, state) do
    Logger.warning("Destroying Pulumi resources at #{project_path}")

    args = ["destroy", "--non-interactive"]
    args = if opts[:yes], do: args ++ ["--yes"], else: args

    args =
      if opts[:stack] do
        args ++ ["--stack", opts[:stack]]
      else
        args
      end

    args =
      if opts[:target] do
        List.wrap(opts[:target])
        |> Enum.reduce(args, fn target, acc ->
          acc ++ ["--target", target]
        end)
      else
        args
      end

    case System.cmd("pulumi", args, cd: project_path, stderr_to_stdout: true) do
      {output, 0} ->
        result = %{
          success: true,
          output: output
        }

        {:reply, {:ok, result}, state}

      {error, exit_code} ->
        {:reply, {:error, "Destroy failed (exit #{exit_code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:validate, project_path}, _from, state) do
    Logger.info("Validating Pulumi configuration at #{project_path}")

    # Use preview with --dry-run to validate
    args = ["preview", "--non-interactive", "--json", "--expect-no-changes"]

    case System.cmd("pulumi", args, cd: project_path, stderr_to_stdout: true) do
      {output, 0} ->
        result = %{
          success: true,
          diagnostics: [],
          output: output
        }

        {:reply, {:ok, result}, state}

      {error, exit_code} ->
        # Parse JSON output for diagnostics if available
        diagnostics =
          case Jason.decode(error) do
            {:ok, %{"diagnostics" => diags}} -> diags
            _ -> []
          end

        result = %{
          success: false,
          diagnostics: diagnostics,
          output: error
        }

        {:reply, {:ok, result}, state}
    end
  end
end
