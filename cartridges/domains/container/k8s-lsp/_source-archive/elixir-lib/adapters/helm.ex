# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyK8s.Adapters.Helm do
  @moduledoc """
  Adapter for Helm - Package manager for Kubernetes.

  ## Configuration

  Detects Helm charts by looking for:
  - `Chart.yaml` in the project root
  - `charts/` directory

  ## Commands

  - `helm install <name> <chart>` - Install a chart
  - `helm upgrade <name> <chart>` - Upgrade a release
  - `helm list` - List releases
  - `helm status <name>` - Get release status
  - `helm rollback <name>` - Rollback a release
  """
  use GenServer
  @behaviour PolyK8s.Adapters.Behaviour

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl PolyK8s.Adapters.Behaviour
  def detect(project_path) do
    chart_yaml = Path.join(project_path, "Chart.yaml")
    charts_dir = Path.join(project_path, "charts")

    detected = File.exists?(chart_yaml) or File.dir?(charts_dir)
    {:ok, detected}
  end

  @impl PolyK8s.Adapters.Behaviour
  def apply(project_path, opts) do
    GenServer.call(__MODULE__, {:apply, project_path, opts})
  end

  @impl PolyK8s.Adapters.Behaviour
  def get_resources(_project_path, opts) do
    GenServer.call(__MODULE__, {:get_resources, opts})
  end

  @impl PolyK8s.Adapters.Behaviour
  def describe(_project_path, opts) do
    GenServer.call(__MODULE__, {:describe, opts})
  end

  @impl PolyK8s.Adapters.Behaviour
  def logs(_project_path, opts) do
    # Helm doesn't directly support logs, delegate to kubectl
    {:error, "Use kubectl adapter for logs functionality"}
  end

  @impl PolyK8s.Adapters.Behaviour
  def rollout(_project_path, opts) do
    GenServer.call(__MODULE__, {:rollback, opts})
  end

  @impl PolyK8s.Adapters.Behaviour
  def version do
    case System.cmd("helm", ["version", "--short"], stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {error, _} -> {:error, error}
    end
  end

  @impl PolyK8s.Adapters.Behaviour
  def metadata do
    %{
      name: "Helm",
      description: "The package manager for Kubernetes",
      config_files: ["Chart.yaml", "values.yaml"],
      manifest_patterns: ["charts/**/*", "templates/**/*.yaml"]
    }
  end

  # Server callbacks

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_call({:apply, project_path, opts}, _from, state) do
    release_name = opts[:release_name] || Path.basename(project_path)
    operation = if opts[:upgrade], do: "upgrade", else: "install"

    Logger.info("Running helm #{operation} for #{release_name}")

    args = [operation, release_name, "."]
    args = maybe_add_namespace(args, opts[:namespace])
    args = maybe_add_values(args, opts[:values])
    args = if opts[:dry_run], do: args ++ ["--dry-run"], else: args
    args = if opts[:create_namespace], do: args ++ ["--create-namespace"], else: args

    case System.cmd("helm", args, cd: project_path, stderr_to_stdout: true) do
      {output, 0} ->
        {:reply, {:ok, %{success: true, output: output}}, state}

      {error, code} ->
        {:reply, {:error, "Helm #{operation} failed (exit #{code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:get_resources, opts}, _from, state) do
    args = ["list"]
    args = maybe_add_namespace(args, opts[:namespace])
    args = if opts[:all_namespaces], do: args ++ ["--all-namespaces"], else: args
    args = args ++ ["-o", "json"]

    case System.cmd("helm", args, stderr_to_stdout: true) do
      {output, 0} ->
        {:reply, {:ok, %{success: true, output: output}}, state}

      {error, code} ->
        {:reply, {:error, "Helm list failed (exit #{code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:describe, opts}, _from, state) do
    release_name = opts[:name]

    if release_name do
      args = ["status", release_name]
      args = maybe_add_namespace(args, opts[:namespace])
      args = args ++ ["-o", "json"]

      case System.cmd("helm", args, stderr_to_stdout: true) do
        {output, 0} ->
          {:reply, {:ok, %{success: true, output: output}}, state}

        {error, code} ->
          {:reply, {:error, "Helm status failed (exit #{code}): #{error}"}, state}
      end
    else
      {:reply, {:error, "release name is required for describe"}, state}
    end
  end

  @impl true
  def handle_call({:rollback, opts}, _from, state) do
    release_name = opts[:resource] || opts[:name]
    revision = opts[:revision]

    if release_name do
      args = ["rollback", release_name]
      args = if revision, do: args ++ [to_string(revision)], else: args
      args = maybe_add_namespace(args, opts[:namespace])

      case System.cmd("helm", args, stderr_to_stdout: true) do
        {output, 0} ->
          {:reply, {:ok, %{success: true, output: output}}, state}

        {error, code} ->
          {:reply, {:error, "Helm rollback failed (exit #{code}): #{error}"}, state}
      end
    else
      {:reply, {:error, "release name is required for rollback"}, state}
    end
  end

  # Helper functions

  defp maybe_add_namespace(args, nil), do: args
  defp maybe_add_namespace(args, namespace), do: args ++ ["-n", namespace]

  defp maybe_add_values(args, nil), do: args
  defp maybe_add_values(args, values_file), do: args ++ ["-f", values_file]
end
