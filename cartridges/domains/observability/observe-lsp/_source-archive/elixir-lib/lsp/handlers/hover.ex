# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyObservability.LSP.Handlers.Hover do
  @moduledoc """
  Provides hover documentation for observability tools.

  Shows:
  - PromQL function documentation
  - LogQL function documentation
  - Grafana panel configuration
  - Metric descriptions
  """

  def handle(params, assigns) do
    uri = get_in(params, ["textDocument", "uri"])
    position = params["position"]

    # Get document text from state
    doc = get_in(assigns, [:documents, uri])
    text = if doc, do: doc.text, else: ""

    # Get word at cursor position
    word = get_word_at_position(text, position["line"], position["character"])

    if word do
      # Get documentation based on file type and word
      docs = cond do
        String.ends_with?(uri, ".promql") or String.ends_with?(uri, ".prom") ->
          get_promql_docs(word)

        String.ends_with?(uri, ".logql") ->
          get_logql_docs(word)

        String.contains?(uri, "grafana") ->
          get_grafana_docs(word)

        true ->
          get_generic_docs(word)
      end

      if docs do
        %{
          "contents" => %{
            "kind" => "markdown",
            "value" => docs
          }
        }
      else
        nil
      end
    else
      nil
    end
  end

  # Extract word at position
  defp get_word_at_position(text, line, character) do
    lines = String.split(text, "\n")
    current_line = Enum.at(lines, line, "")

    # Find word boundaries
    before = String.slice(current_line, 0, character) |> String.reverse()
    after_text = String.slice(current_line, character, String.length(current_line))

    start = Regex.run(~r/^[a-zA-Z0-9_]*/, before) |> List.first() |> String.reverse()
    end_part = Regex.run(~r/^[a-zA-Z0-9_]*/, after_text) |> List.first()

    word = start <> end_part
    if String.length(word) > 0, do: word, else: nil
  end

  # PromQL documentation
  defp get_promql_docs(word) do
    docs = %{
      "rate" => "**rate(range-vector)** - Per-second rate of increase\n\nCalculates the per-second average rate of increase over a time range.\n\nExample: `rate(http_requests_total[5m])`",
      "irate" => "**irate(range-vector)** - Instant rate of increase\n\nCalculates the per-second instant rate based on the last two data points.\n\nExample: `irate(http_requests_total[5m])`",
      "increase" => "**increase(range-vector)** - Total increase\n\nCalculates the total increase over a time range.\n\nExample: `increase(http_requests_total[1h])`",
      "sum" => "**sum(instant-vector)** - Sum aggregation\n\nCalculates sum over dimensions.\n\nExample: `sum by (job) (http_requests_total)`",
      "avg" => "**avg(instant-vector)** - Average aggregation\n\nCalculates average over dimensions.\n\nExample: `avg by (instance) (cpu_usage)`",
      "min" => "**min(instant-vector)** - Minimum aggregation\n\nReturns minimum value over dimensions.",
      "max" => "**max(instant-vector)** - Maximum aggregation\n\nReturns maximum value over dimensions.",
      "count" => "**count(instant-vector)** - Count aggregation\n\nCounts the number of elements.",
      "histogram_quantile" => "**histogram_quantile(φ, instant-vector)** - Histogram quantile\n\nCalculates φ-quantile from histogram buckets.\n\nExample: `histogram_quantile(0.95, rate(http_request_duration_bucket[5m]))`",
      "delta" => "**delta(range-vector)** - Difference between values\n\nCalculates the difference between first and last value.",
      "deriv" => "**deriv(range-vector)** - Per-second derivative\n\nCalculates the per-second derivative using linear regression."
    }

    Map.get(docs, word)
  end

  # LogQL documentation
  defp get_logql_docs(word) do
    docs = %{
      "rate" => "**rate(log-range-vector)** - Per-second rate\n\nCalculates the per-second rate of log entries.\n\nExample: `rate({job=\"varlogs\"}[5m])`",
      "count_over_time" => "**count_over_time(log-range-vector)** - Count logs\n\nCounts log entries over a time range.\n\nExample: `count_over_time({job=\"varlogs\"}[5m])`",
      "bytes_over_time" => "**bytes_over_time(log-range-vector)** - Bytes count\n\nCounts bytes of log entries over time.",
      "sum" => "**sum(vector)** - Sum aggregation\n\nSums values across dimensions.",
      "avg" => "**avg(vector)** - Average aggregation\n\nCalculates average across dimensions.",
      "json" => "**| json** - Parse JSON logs\n\nExtracts fields from JSON log lines.\n\nExample: `{job=\"app\"} | json | level=\"error\"`",
      "logfmt" => "**| logfmt** - Parse logfmt logs\n\nExtracts fields from logfmt log lines.",
      "regexp" => "**| regexp \"pattern\"** - Extract with regex\n\nExtracts fields using regular expressions.",
      "pattern" => "**| pattern \"<field>...\"** - Parse with pattern\n\nParses log lines using a pattern template."
    }

    Map.get(docs, word)
  end

  # Grafana documentation
  defp get_grafana_docs(word) do
    docs = %{
      "panels" => "**panels** - Dashboard panels array\n\nContains all panels in the dashboard.",
      "targets" => "**targets** - Data source queries\n\nDefines queries for panel data sources.",
      "datasource" => "**datasource** - Data source configuration\n\nSpecifies which data source to use.",
      "title" => "**title** - Panel title\n\nThe display title for the panel.",
      "type" => "**type** - Panel type\n\nPanel visualization type (graph, table, stat, etc.).",
      "gridPos" => "**gridPos** - Panel grid position\n\nDefines panel position and size in the grid.",
      "fieldConfig" => "**fieldConfig** - Field configuration\n\nConfigures field display and transformation.",
      "options" => "**options** - Panel options\n\nPanel-specific display options."
    }

    Map.get(docs, word)
  end

  # Generic observability documentation
  defp get_generic_docs(word) do
    docs = %{
      "scrape_configs" => "**scrape_configs** - Prometheus scrape configuration\n\nDefines targets to scrape metrics from.",
      "alerting" => "**alerting** - Alerting configuration\n\nConfigures alert managers.",
      "rule_files" => "**rule_files** - Recording and alerting rules\n\nPaths to rule files.",
      "global" => "**global** - Global configuration\n\nDefault settings for all jobs."
    }

    Map.get(docs, word)
  end
end
