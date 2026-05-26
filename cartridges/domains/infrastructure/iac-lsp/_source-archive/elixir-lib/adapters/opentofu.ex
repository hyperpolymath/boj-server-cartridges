# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyIaC.Adapters.OpenTofu do
  @moduledoc """
  Adapter for OpenTofu - FOSS drop-in replacement for Terraform.

  ## Configuration

  OpenTofu uses `.tf` files (HCL) at the project root. Common files:
  - `main.tf` - Main configuration
  - `variables.tf` - Variable definitions
  - `outputs.tf` - Output definitions
  - `terraform.tfvars` or `*.auto.tfvars` - Variable values

  ## Commands

  - `tofu init` - Initialize working directory
  - `tofu plan` - Generate execution plan
  - `tofu apply` - Apply changes
  - `tofu destroy` - Destroy managed infrastructure
  - `tofu validate` - Validate configuration

  ## FOSS-First Policy

  OpenTofu is preferred over Terraform as it's fully open source under MPL-2.0,
  while Terraform moved to BSL (Business Source License) in 2023.
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
    tf_files =
      Path.wildcard(Path.join(project_path, "*.tf")) ++
        Path.wildcard(Path.join(project_path, "**/*.tf"))

    {:ok, length(tf_files) > 0}
  end

  @impl PolyIaC.Adapters.Behaviour
  def init(project_path, opts) do
    GenServer.call(__MODULE__, {:init, project_path, opts}, :infinity)
  end

  @impl PolyIaC.Adapters.Behaviour
  def plan(project_path, opts) do
    GenServer.call(__MODULE__, {:plan, project_path, opts}, :infinity)
  end

  @impl PolyIaC.Adapters.Behaviour
  def apply(project_path, opts) do
    GenServer.call(__MODULE__, {:apply, project_path, opts}, :infinity)
  end

  @impl PolyIaC.Adapters.Behaviour
  def destroy(project_path, opts) do
    GenServer.call(__MODULE__, {:destroy, project_path, opts}, :infinity)
  end

  @impl PolyIaC.Adapters.Behaviour
  def validate(project_path) do
    GenServer.call(__MODULE__, {:validate, project_path}, :infinity)
  end

  @impl PolyIaC.Adapters.Behaviour
  def version do
    case System.cmd("tofu", ["version", "-json"], stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, %{"terraform_version" => version}} ->
            {:ok, version}

          _ ->
            # Fallback to text parsing
            case System.cmd("tofu", ["version"], stderr_to_stdout: true) do
              {text_output, 0} ->
                version =
                  text_output
                  |> String.split("\n")
                  |> List.first()
                  |> String.replace("OpenTofu v", "")
                  |> String.trim()

                {:ok, version}

              {error, _} ->
                {:error, error}
            end
        end

      {error, _} ->
        {:error, error}
    end
  end

  @impl PolyIaC.Adapters.Behaviour
  def metadata do
    %{
      name: "OpenTofu",
      language: "HCL",
      description: "FOSS drop-in replacement for Terraform (MPL-2.0)",
      config_files: ["*.tf", "*.tfvars"],
      state_files: ["terraform.tfstate", ".terraform/"],
      foss_first: true
    }
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %{operations: %{}}}
  end

  @impl true
  def handle_call({:init, project_path, opts}, _from, state) do
    Logger.info("Initializing OpenTofu project at #{project_path}")

    args = ["init"]
    args = if opts[:upgrade], do: args ++ ["-upgrade"], else: args
    args = if opts[:reconfigure], do: args ++ ["-reconfigure"], else: args

    args =
      if opts[:backend_config] do
        Enum.reduce(opts[:backend_config], args, fn {key, value}, acc ->
          acc ++ ["-backend-config=#{key}=#{value}"]
        end)
      else
        args
      end

    case System.cmd("tofu", args, cd: project_path, stderr_to_stdout: true) do
      {output, 0} ->
        result = %{
          success: true,
          output: output
        }

        {:reply, {:ok, result}, state}

      {error, exit_code} ->
        {:reply, {:error, "Init failed (exit #{exit_code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:plan, project_path, opts}, _from, state) do
    Logger.info("Planning OpenTofu changes at #{project_path}")

    args = ["plan", "-input=false", "-no-color"]

    args =
      if opts[:var_file] do
        args ++ ["-var-file=#{opts[:var_file]}"]
      else
        args
      end

    args =
      if opts[:vars] do
        Enum.reduce(opts[:vars], args, fn {key, value}, acc ->
          acc ++ ["-var", "#{key}=#{value}"]
        end)
      else
        args
      end

    args = if opts[:destroy], do: args ++ ["-destroy"], else: args
    args = if opts[:out], do: args ++ ["-out=#{opts[:out]}"], else: args

    args =
      if opts[:target] do
        List.wrap(opts[:target])
        |> Enum.reduce(args, fn target, acc ->
          acc ++ ["-target=#{target}"]
        end)
      else
        args
      end

    case System.cmd("tofu", args, cd: project_path, stderr_to_stdout: true) do
      {output, 0} ->
        result = %{
          success: true,
          output: output,
          changes_detected: String.contains?(output, "Plan:")
        }

        {:reply, {:ok, result}, state}

      {error, exit_code} ->
        {:reply, {:error, "Plan failed (exit #{exit_code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:apply, project_path, opts}, _from, state) do
    Logger.info("Applying OpenTofu changes at #{project_path}")

    args = ["apply", "-input=false", "-no-color"]
    args = if opts[:auto_approve], do: args ++ ["-auto-approve"], else: args

    args =
      if opts[:plan_file] do
        args ++ [opts[:plan_file]]
      else
        args =
          if opts[:var_file] do
            args ++ ["-var-file=#{opts[:var_file]}"]
          else
            args
          end

        args =
          if opts[:vars] do
            Enum.reduce(opts[:vars], args, fn {key, value}, acc ->
              acc ++ ["-var", "#{key}=#{value}"]
            end)
          else
            args
          end

        args
      end

    case System.cmd("tofu", args, cd: project_path, stderr_to_stdout: true) do
      {output, 0} ->
        result = %{
          success: true,
          output: output
        }

        {:reply, {:ok, result}, state}

      {error, exit_code} ->
        {:reply, {:error, "Apply failed (exit #{exit_code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:destroy, project_path, opts}, _from, state) do
    Logger.warning("Destroying OpenTofu resources at #{project_path}")

    args = ["destroy", "-input=false", "-no-color"]
    args = if opts[:auto_approve], do: args ++ ["-auto-approve"], else: args

    args =
      if opts[:var_file] do
        args ++ ["-var-file=#{opts[:var_file]}"]
      else
        args
      end

    args =
      if opts[:vars] do
        Enum.reduce(opts[:vars], args, fn {key, value}, acc ->
          acc ++ ["-var", "#{key}=#{value}"]
        end)
      else
        args
      end

    case System.cmd("tofu", args, cd: project_path, stderr_to_stdout: true) do
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
    Logger.info("Validating OpenTofu configuration at #{project_path}")

    case System.cmd("tofu", ["validate", "-json"], cd: project_path, stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, validation_result} ->
            result = %{
              success: validation_result["valid"] == true,
              diagnostics: validation_result["diagnostics"] || [],
              output: output
            }

            {:reply, {:ok, result}, state}

          {:error, _} ->
            {:reply, {:error, "Failed to parse validation output"}, state}
        end

      {error, exit_code} ->
        {:reply, {:error, "Validate failed (exit #{exit_code}): #{error}"}, state}
    end
  end
end
