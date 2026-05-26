# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyK8s.Adapters.Kubectl do
  @moduledoc """
  Adapter for kubectl - Kubernetes command-line tool.

  ## Configuration

  Detects standard Kubernetes manifest directories:
  - `k8s/`
  - `kubernetes/`
  - `manifests/`
  - Or any `.yaml`/`.yml` files with `apiVersion` and `kind` fields

  ## Commands

  - `kubectl apply -f <path>` - Apply manifests
  - `kubectl get <resource>` - Get resources
  - `kubectl describe <resource> <name>` - Describe resource
  - `kubectl logs <pod>` - Get pod logs
  - `kubectl rollout status deployment/<name>` - Check rollout status
  """
  use GenServer
  @behaviour PolyK8s.Adapters.Behaviour

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl PolyK8s.Adapters.Behaviour
  def detect(project_path) do
    manifest_dirs = ["k8s", "kubernetes", "manifests"]

    detected =
      Enum.any?(manifest_dirs, fn dir ->
        Path.join(project_path, dir) |> File.dir?()
      end) or has_k8s_manifests?(project_path)

    {:ok, detected}
  end

  defp has_k8s_manifests?(project_path) do
    Path.wildcard(Path.join(project_path, "*.{yaml,yml}"))
    |> Enum.any?(fn file ->
      case File.read(file) do
        {:ok, content} ->
          String.contains?(content, "apiVersion:") and String.contains?(content, "kind:")

        _ ->
          false
      end
    end)
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
  def describe(project_path, opts) do
    GenServer.call(__MODULE__, {:describe, project_path, opts})
  end

  @impl PolyK8s.Adapters.Behaviour
  def logs(project_path, opts) do
    GenServer.call(__MODULE__, {:logs, project_path, opts})
  end

  @impl PolyK8s.Adapters.Behaviour
  def rollout(project_path, opts) do
    GenServer.call(__MODULE__, {:rollout, project_path, opts})
  end

  @impl PolyK8s.Adapters.Behaviour
  def version do
    case System.cmd("kubectl", ["version", "--client", "--short"], stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {error, _} -> {:error, error}
    end
  end

  @impl PolyK8s.Adapters.Behaviour
  def metadata do
    %{
      name: "kubectl",
      description: "Kubernetes command-line tool for managing cluster resources",
      config_files: ["~/.kube/config"],
      manifest_patterns: ["k8s/**/*.yaml", "kubernetes/**/*.yaml", "manifests/**/*.yaml"]
    }
  end

  # Server callbacks

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_call({:apply, project_path, opts}, _from, state) do
    Logger.info("Applying Kubernetes manifests at #{project_path}")

    args = ["apply", "-f", manifest_path(project_path)]
    args = maybe_add_namespace(args, opts[:namespace])
    args = maybe_add_context(args, opts[:context])
    args = maybe_add_dry_run(args, opts[:dry_run])

    case System.cmd("kubectl", args, cd: project_path, stderr_to_stdout: true) do
      {output, 0} ->
        {:reply, {:ok, %{success: true, output: output}}, state}

      {error, code} ->
        {:reply, {:error, "Apply failed (exit #{code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:get_resources, _project_path, opts}, _from, state) do
    resource_type = opts[:resource_type] || "all"
    args = ["get", resource_type]
    args = maybe_add_namespace(args, opts[:namespace])
    args = if opts[:all_namespaces], do: args ++ ["--all-namespaces"], else: args
    args = if opts[:selector], do: args ++ ["-l", opts[:selector]], else: args
    args = args ++ ["-o", "json"]

    case System.cmd("kubectl", args, stderr_to_stdout: true) do
      {output, 0} ->
        {:reply, {:ok, %{success: true, output: output}}, state}

      {error, code} ->
        {:reply, {:error, "Get failed (exit #{code}): #{error}"}, state}
    end
  end

  @impl true
  def handle_call({:describe, _project_path, opts}, _from, state) do
    resource_type = opts[:resource_type]
    name = opts[:name]

    if resource_type && name do
      args = ["describe", resource_type, name]
      args = maybe_add_namespace(args, opts[:namespace])

      case System.cmd("kubectl", args, stderr_to_stdout: true) do
        {output, 0} ->
          {:reply, {:ok, %{success: true, output: output}}, state}

        {error, code} ->
          {:reply, {:error, "Describe failed (exit #{code}): #{error}"}, state}
      end
    else
      {:reply, {:error, "resource_type and name are required for describe"}, state}
    end
  end

  @impl true
  def handle_call({:logs, _project_path, opts}, _from, state) do
    pod = opts[:pod]

    if pod do
      args = ["logs", pod]
      args = maybe_add_namespace(args, opts[:namespace])
      args = if opts[:container], do: args ++ ["-c", opts[:container]], else: args
      args = if opts[:follow], do: args ++ ["-f"], else: args
      args = if opts[:tail], do: args ++ ["--tail", to_string(opts[:tail])], else: args

      case System.cmd("kubectl", args, stderr_to_stdout: true) do
        {output, 0} ->
          {:reply, {:ok, %{success: true, output: output}}, state}

        {error, code} ->
          {:reply, {:error, "Logs failed (exit #{code}): #{error}"}, state}
      end
    else
      {:reply, {:error, "pod name is required for logs"}, state}
    end
  end

  @impl true
  def handle_call({:rollout, _project_path, opts}, _from, state) do
    resource = opts[:resource]
    operation = opts[:operation] || :status

    if resource do
      args = ["rollout", to_string(operation), resource]
      args = maybe_add_namespace(args, opts[:namespace])

      case System.cmd("kubectl", args, stderr_to_stdout: true) do
        {output, 0} ->
          {:reply, {:ok, %{success: true, output: output}}, state}

        {error, code} ->
          {:reply, {:error, "Rollout #{operation} failed (exit #{code}): #{error}"}, state}
      end
    else
      {:reply, {:error, "resource name is required for rollout"}, state}
    end
  end

  # Helper functions

  defp manifest_path(project_path) do
    cond do
      File.dir?(Path.join(project_path, "k8s")) -> "k8s/"
      File.dir?(Path.join(project_path, "kubernetes")) -> "kubernetes/"
      File.dir?(Path.join(project_path, "manifests")) -> "manifests/"
      true -> "."
    end
  end

  defp maybe_add_namespace(args, nil), do: args
  defp maybe_add_namespace(args, namespace), do: args ++ ["-n", namespace]

  defp maybe_add_context(args, nil), do: args
  defp maybe_add_context(args, context), do: args ++ ["--context", context]

  defp maybe_add_dry_run(args, false), do: args
  defp maybe_add_dry_run(args, nil), do: args
  defp maybe_add_dry_run(args, :client), do: args ++ ["--dry-run=client"]
  defp maybe_add_dry_run(args, :server), do: args ++ ["--dry-run=server"]
end
