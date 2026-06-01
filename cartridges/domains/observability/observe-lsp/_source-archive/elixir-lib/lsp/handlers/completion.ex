# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyObservability.LSP.Handlers.Completion do
  @moduledoc """
  Provides auto-completion for observability tools.

  Supports:
  - Prometheus query language (PromQL)
  - Grafana dashboard JSON
  - Loki LogQL
  - Jaeger configuration
  """

  def handle(params, assigns) do
    uri = get_in(params, ["textDocument", "uri"])
    position = params["position"]

    # Get document text from state
    doc = get_in(assigns, [:documents, uri])
    text = if doc, do: doc.text, else: ""

    # Get line and character position
    line = position["line"]
    character = position["character"]

    # Get context around cursor
    context = get_line_context(text, line, character)

    # Provide completions based on file type and detected tools
    completions = cond do
      String.ends_with?(uri, ".promql") or String.ends_with?(uri, ".prom") ->
        complete_promql(context)

      String.ends_with?(uri, ".logql") ->
        complete_logql(context)

      String.contains?(uri, "grafana") and String.ends_with?(uri, ".json") ->
        complete_grafana(context)

      String.ends_with?(uri, ".yaml") or String.ends_with?(uri, ".yml") ->
        complete_yaml(context, assigns.detected_tools)

      true ->
        []
    end

    completions
  end

  # Extract line context around cursor
  defp get_line_context(text, line, character) do
    lines = String.split(text, "\n")
    current_line = Enum.at(lines, line, "")
    before_cursor = String.slice(current_line, 0, character)

    %{
      line: current_line,
      before_cursor: before_cursor,
      trigger: get_trigger(before_cursor)
    }
  end

  # Detect completion trigger
  defp get_trigger(text) do
    cond do
      String.match?(text, ~r/\w+\{$/) -> :metric_label
      String.match?(text, ~r/by\s*\($/) -> :aggregation
      String.match?(text, ~r/rate\($/) -> :function_arg
      String.ends_with?(text, "{") -> :json_key
      true -> :none
    end
  end

  # PromQL completions
  defp complete_promql(context) do
    case context.trigger do
      :metric_label ->
        ["job", "instance", "namespace", "pod", "container"]
        |> Enum.map(&create_completion_item(&1, "field"))

      :aggregation ->
        ["job", "instance", "namespace", "label"]
        |> Enum.map(&create_completion_item(&1, "field"))

      :function_arg ->
        []

      _ ->
        # Metric functions and aggregations
        functions = [
          "rate", "irate", "increase", "delta", "deriv",
          "sum", "avg", "min", "max", "count",
          "histogram_quantile", "label_replace", "label_join"
        ]

        functions
        |> Enum.map(&create_completion_item(&1, "function"))
    end
  end

  # LogQL completions
  defp complete_logql(context) do
    case context.trigger do
      :metric_label ->
        ["job", "filename", "stream", "level"]
        |> Enum.map(&create_completion_item(&1, "field"))

      _ ->
        # LogQL functions
        functions = [
          "rate", "count_over_time", "bytes_over_time",
          "sum", "avg", "min", "max", "count",
          "json", "logfmt", "regexp", "pattern"
        ]

        functions
        |> Enum.map(&create_completion_item(&1, "function"))
    end
  end

  # Grafana dashboard completions
  defp complete_grafana(context) do
    case context.trigger do
      :json_key ->
        [
          "panels", "targets", "datasource", "title",
          "type", "gridPos", "fieldConfig", "options"
        ]
        |> Enum.map(&create_completion_item(&1, "field"))

      _ ->
        []
    end
  end

  # YAML completions for Prometheus/Jaeger config
  defp complete_yaml(context, tools) do
    base_completions = [
      "scrape_configs", "alerting", "rule_files",
      "global", "remote_write", "remote_read"
    ]

    if :prometheus in tools do
      base_completions
      |> Enum.map(&create_completion_item(&1, "field"))
    else
      []
    end
  end

  # Create LSP completion item
  defp create_completion_item(label, kind_str) do
    kind = case kind_str do
      "function" -> 3    # Function
      "field" -> 5       # Field
      "keyword" -> 14    # Keyword
      _ -> 1             # Text
    end

    %{
      "label" => label,
      "kind" => kind,
      "detail" => "#{kind_str}",
      "insertText" => label
    }
  end
end
