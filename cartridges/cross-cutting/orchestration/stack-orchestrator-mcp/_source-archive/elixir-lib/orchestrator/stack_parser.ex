# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyOrchestrator.Orchestrator.StackParser do
  @moduledoc """
  Parses stack.compose.toml files into executable orchestration plans.

  Handles:
  - TOML parsing and validation
  - Variable interpolation (${var} syntax)
  - Component dependency resolution
  - Security policy extraction
  - LSP server routing
  """

  @doc """
  Parse a stack.compose.toml file.

  Returns:
  - `{:ok, stack}` - Parsed and validated stack
  - `{:error, reason}` - Parse or validation error
  """
  def parse_file(path) do
    with {:ok, content} <- File.read(path),
         {:ok, toml} <- Toml.decode(content),
         {:ok, stack} <- validate_structure(toml),
         {:ok, stack} <- interpolate_variables(stack) do
      {:ok, stack}
    end
  end

  @doc """
  Parse TOML content from a string.
  """
  def parse_string(content) do
    with {:ok, toml} <- Toml.decode(content),
         {:ok, stack} <- validate_structure(toml),
         {:ok, stack} <- interpolate_variables(stack) do
      {:ok, stack}
    end
  end

  @doc """
  Validate stack structure against schema.
  """
  def validate_structure(toml) do
    with :ok <- validate_metadata(toml["metadata"]),
         :ok <- validate_components(toml["components"]),
         :ok <- validate_security(toml["security"]) do
      {:ok, toml}
    end
  end

  @doc """
  Interpolate variables throughout the stack.

  Supports:
  - ${var} - From orchestration.variables
  - ${component.output} - From component outputs
  - ${env:VAR} - From environment variables
  """
  def interpolate_variables(stack) do
    variables = build_variable_context(stack)

    interpolated_stack =
      stack
      |> interpolate_components(variables)
      |> interpolate_verification(variables)

    {:ok, interpolated_stack}
  end

  @doc """
  Extract dependency graph from components.

  Returns a Graph struct with:
  - Vertices: component IDs
  - Edges: dependency relationships
  """
  def extract_dependency_graph(stack) do
    components = stack["components"] || []

    graph = Graph.new(type: :directed)

    # Add all components as vertices
    graph = Enum.reduce(components, graph, fn component, g ->
      Graph.add_vertex(g, component["id"], component)
    end)

    # Add dependency edges
    graph = Enum.reduce(components, graph, fn component, g ->
      depends_on = component["depends_on"] || []
      Enum.reduce(depends_on, g, fn dep, acc ->
        Graph.add_edge(acc, dep, component["id"])
      end)
    end)

    {:ok, graph}
  end

  @doc """
  Group components by execution phase.

  Returns: %{1 => [components...], 2 => [components...], ...}
  """
  def group_by_phase(stack) do
    components = stack["components"] || []

    components
    |> Enum.group_by(fn c -> c["phase"] || 1 end)
    |> Map.new(fn {phase, comps} ->
      {phase, Enum.sort_by(comps, & &1["id"])}
    end)
  end

  @doc """
  Extract security policies from stack.
  """
  def extract_security_policies(stack) do
    security = stack["security"] || %{}

    %{
      threat_model: security["threat_model"],
      attack_surface_score: security["attack_surface_score"],
      validated: security["validated"] || false,
      policies: security["policies"] || [],
      constraints: security["constraints"] || []
    }
  end

  # Private functions

  defp validate_metadata(nil), do: {:error, "Missing metadata section"}
  defp validate_metadata(metadata) do
    required = ["version", "name"]
    missing = Enum.filter(required, &(!Map.has_key?(metadata, &1)))

    if Enum.empty?(missing) do
      :ok
    else
      {:error, "Missing required metadata fields: #{Enum.join(missing, ", ")}"}
    end
  end

  defp validate_components(nil), do: {:error, "Missing components section"}
  defp validate_components([]), do: {:error, "No components defined"}
  defp validate_components(components) when is_list(components) do
    # Validate each component has required fields
    Enum.reduce_while(components, :ok, fn component, _acc ->
      case validate_component(component) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_component(component) do
    required = ["id", "type", "lsp_server"]
    missing = Enum.filter(required, &(!Map.has_key?(component, &1)))

    if Enum.empty?(missing) do
      :ok
    else
      {:error, "Component #{component["id"]}: missing #{Enum.join(missing, ", ")}"}
    end
  end

  defp validate_security(nil), do: :ok  # Security section is optional
  defp validate_security(_security), do: :ok

  defp build_variable_context(stack) do
    orchestration = stack["orchestration"] || %{}
    variables = orchestration["variables"] || %{}

    # Add environment variables
    env_vars = System.get_env()
    |> Enum.map(fn {k, v} -> {"env:#{k}", v} end)
    |> Map.new()

    Map.merge(variables, env_vars)
  end

  defp interpolate_components(stack, variables) do
    components = stack["components"] || []

    interpolated = Enum.map(components, fn component ->
      component
      |> interpolate_map(variables)
    end)

    Map.put(stack, "components", interpolated)
  end

  defp interpolate_verification(stack, variables) do
    verification = stack["verification"] || []

    interpolated = Enum.map(verification, fn v ->
      interpolate_map(v, variables)
    end)

    Map.put(stack, "verification", interpolated)
  end

  defp interpolate_map(map, variables) when is_map(map) do
    Map.new(map, fn {k, v} ->
      {k, interpolate_value(v, variables)}
    end)
  end

  defp interpolate_value(value, variables) when is_binary(value) do
    # Replace ${var} with actual values
    Regex.replace(~r/\$\{([^}]+)\}/, value, fn _, var_name ->
      Map.get(variables, var_name, "${#{var_name}}")  # Keep unresolved
    end)
  end

  defp interpolate_value(value, variables) when is_list(value) do
    Enum.map(value, &interpolate_value(&1, variables))
  end

  defp interpolate_value(value, variables) when is_map(value) do
    interpolate_map(value, variables)
  end

  defp interpolate_value(value, _variables), do: value
end
