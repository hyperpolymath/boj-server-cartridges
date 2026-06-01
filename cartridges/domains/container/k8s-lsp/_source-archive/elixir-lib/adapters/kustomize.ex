# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyK8s.Adapters.Kustomize do
  @moduledoc """
  Adapter for Kustomize - Kubernetes native configuration management.

  ## Configuration

  Detects Kustomize projects by looking for:
  - `kustomization.yaml`
  - `kustomization.yml`

  ## Commands

  - `kubectl apply -k <path>` - Apply kustomization
  - `kustomize build <path>` - Build and view manifests
  """
  use GenServer
  @behaviour PolyK8s.Adapters.Behaviour

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl PolyK8s.Adapters.Behaviour
  def detect(project_path) do
    kustomization_files = ["kustomization.yaml", "kustomization.yml"]

    detected =
      Enum.any?(kustomization_files, fn file ->
        Path.join(project_path, file) |> File.exists?()
      end)

    {:ok, detected}
  end

  @impl PolyK8s.Adapters.Behaviour
  def apply(project_path, opts) do
    GenServer.call(__MODULE__, {:apply, project_path, opts})
  end

  @impl PolyK8s.Adapters.Behaviour
  def get_resources(project_path, opts) do
    GenServer.call(__MODULE__, {:get_resources, project_path, opts})
  end

  @impl PolyK8s.Adapters.Behaviour
  def describe(_project_path, _opts) do
    {:error, "Use kubectl adapter for describe functionality"}
  end

  @impl PolyK8s.Adapters.Behaviour
  def logs(_project_path, _opts) do
    {:error, "Use kubectl adapter for logs functionality"}
  end

  @impl PolyK8s.Adapters.Behaviour
  def rollout(_project_path, _opts) do
    {:error, "Use kubectl adapter for rollout functionality"}
  end

  @impl PolyK8s.Adapters.Behaviour
  def version do
    case System.cmd("kustomize", ["version", "--short"], stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {error, _} -> {:error, error}
    end
  end

  @impl PolyK8s.Adapters.Behaviour
  def metadata do
    %{
      name: "Kustomize",
      description: "Kubernetes native configuration management",
      config_files: ["kustomization.yaml", "kustomization.yml"],
      manifest_patterns: ["base/**/*.yaml", "overlays/**/*.yaml"]
    }
  end

  # Server callbacks

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_call({:apply, project_path, opts}, _from, state) do
    Logger.info("Applying Kustomize configuration at #{project_path}")

    # Use kubectl apply -k for kustomize
    args = ["apply", "-k", "."]
    args = maybe_add_namespace(args, opts[:namespace])
    args = maybe_add_context(args, opts[:context])
    args = maybe_add_dry_run(args, opts[:dry_run])

    case System.cmd("kubectl", args, cd: project_path, stderr_to_stdout: true) do
      {output, 0} ->
        {:reply, {:ok, %{success: true, output: output}}, state}

      {error, code} ->
        {:reply, {:error, "Kustomize apply failed (exit #{code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:get_resources, project_path, opts}, _from, state) do
    Logger.info("Building Kustomize configuration at #{project_path}")

    # Build and display the manifests
    overlay = opts[:overlay] || "."

    case System.cmd("kustomize", ["build", overlay], cd: project_path, stderr_to_stdout: true) do
      {output, 0} ->
        {:reply, {:ok, %{success: true, output: output}}, state}

      {error, code} ->
        {:reply, {:error, "Kustomize build failed (exit #{code}): #{error}"}, state}
    end
  end

  # Helper functions

  defp maybe_add_namespace(args, nil), do: args
  defp maybe_add_namespace(args, namespace), do: args ++ ["-n", namespace]

  defp maybe_add_context(args, nil), do: args
  defp maybe_add_context(args, context), do: args ++ ["--context", context]

  defp maybe_add_dry_run(args, false), do: args
  defp maybe_add_dry_run(args, nil), do: args
  defp maybe_add_dry_run(args, :client), do: args ++ ["--dry-run=client"]
  defp maybe_add_dry_run(args, :server), do: args ++ ["--dry-run=server"]
end
