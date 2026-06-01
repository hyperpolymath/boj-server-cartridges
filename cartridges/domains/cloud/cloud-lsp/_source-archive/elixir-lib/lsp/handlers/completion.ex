# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyCloud.LSP.Handlers.Completion do
  @moduledoc """
  Provides auto-completion for cloud configuration files.

  Supports:
  - Cloud provider resources (AWS, GCP, Azure, DigitalOcean)
  - Configuration keys
  - Service names and regions
  """

  def handle(params, assigns) do
    uri = get_in(params, ["textDocument", "uri"])
    position = params["position"]

    # Get document text from state
    doc = get_in(assigns, [:documents, uri])
    text = if doc, do: doc.text, else: ""

    # Get line context
    context = get_line_context(text, position["line"], position["character"])

    # Provide completions based on cloud provider
    completions = case assigns[:detected_provider] do
      :aws -> complete_aws(context)
      :gcp -> complete_gcp(context)
      :azure -> complete_azure(context)
      :digitalocean -> complete_digitalocean(context)
      _ -> complete_generic(context)
    end

    completions
  end

  defp get_line_context(text, line, character) do
    lines = String.split(text, "\n")
    current_line = Enum.at(lines, line, "")
    before_cursor = String.slice(current_line, 0, character)

    %{
      line: current_line,
      before_cursor: before_cursor
    }
  end

  defp complete_aws(_context) do
    [
      "EC2", "S3", "Lambda", "RDS", "DynamoDB", "CloudFront", "Route53",
      "us-east-1", "us-west-2", "eu-west-1", "ap-southeast-1"
    ]
    |> Enum.map(&create_completion_item(&1, "property"))
  end

  defp complete_gcp(_context) do
    [
      "Compute Engine", "Cloud Storage", "Cloud Functions", "Cloud SQL",
      "us-central1", "europe-west1", "asia-east1"
    ]
    |> Enum.map(&create_completion_item(&1, "property"))
  end

  defp complete_azure(_context) do
    [
      "Virtual Machines", "Blob Storage", "Functions", "SQL Database",
      "eastus", "westeurope", "southeastasia"
    ]
    |> Enum.map(&create_completion_item(&1, "property"))
  end

  defp complete_digitalocean(_context) do
    [
      "Droplets", "Spaces", "Functions", "Databases",
      "nyc1", "sfo2", "lon1", "sgp1"
    ]
    |> Enum.map(&create_completion_item(&1, "property"))
  end

  defp complete_generic(_context) do
    ["provider", "region", "instance_type", "storage"]
    |> Enum.map(&create_completion_item(&1, "property"))
  end

  defp create_completion_item(label, kind_str) do
    kind = case kind_str do
      "property" -> 10  # Property
      _ -> 1            # Text
    end

    %{
      "label" => label,
      "kind" => kind,
      "detail" => kind_str,
      "insertText" => label
    }
  end
end
