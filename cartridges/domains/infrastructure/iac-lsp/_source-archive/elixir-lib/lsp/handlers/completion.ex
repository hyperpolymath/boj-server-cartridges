# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyIaC.LSP.Handlers.Completion do
  @moduledoc """
  Provides auto-completion for Infrastructure as Code.

  Supports:
  - OpenTofu/Terraform resources and data sources
  - Pulumi resource types and functions
  - Configuration blocks and attributes
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

    # Provide completions based on context and detected IaC
    completions = case assigns.detected_iac do
      :opentofu -> complete_opentofu(context, uri)
      :pulumi -> complete_pulumi(context, uri)
      _ -> complete_generic(context)
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
      String.match?(text, ~r/resource\s+"?\w*$/) -> :resource_type
      String.match?(text, ~r/data\s+"?\w*$/) -> :data_source
      String.match?(text, ~r/provider\s+"?\w*$/) -> :provider
      String.match?(text, ~r/\w+\.\w*$/) -> :attribute
      String.ends_with?(text, "new ") -> :pulumi_resource
      true -> :none
    end
  end

  # OpenTofu/Terraform completions
  defp complete_opentofu(context, uri) do
    case context.trigger do
      :resource_type ->
        if String.ends_with?(uri, ".tf") do
          [
            "aws_instance", "aws_s3_bucket", "aws_vpc", "aws_subnet",
            "google_compute_instance", "google_storage_bucket",
            "azurerm_virtual_machine", "azurerm_storage_account"
          ]
          |> Enum.map(&create_completion_item(&1, "class"))
        else
          []
        end

      :data_source ->
        [
          "aws_ami", "aws_availability_zones", "aws_vpc",
          "google_compute_image", "azurerm_image"
        ]
        |> Enum.map(&create_completion_item(&1, "interface"))

      :provider ->
        ["aws", "google", "azurerm", "kubernetes", "helm", "random"]
        |> Enum.map(&create_completion_item(&1, "module"))

      :attribute ->
        ["id", "arn", "name", "tags", "vpc_id", "subnet_id", "cidr_block"]
        |> Enum.map(&create_completion_item(&1, "field"))

      _ ->
        ["resource", "data", "provider", "variable", "output", "locals", "module"]
        |> Enum.map(&create_completion_item(&1, "keyword"))
    end
  end

  # Pulumi completions
  defp complete_pulumi(context, uri) do
    case context.trigger do
      :pulumi_resource ->
        cond do
          String.contains?(uri, ".ts") or String.contains?(uri, ".js") ->
            ["aws.ec2.Instance", "aws.s3.Bucket", "aws.ec2.Vpc", "aws.ec2.Subnet"]
            |> Enum.map(&create_completion_item(&1, "class"))

          String.contains?(uri, ".py") ->
            ["aws.ec2.Instance", "aws.s3.Bucket", "aws.ec2.Vpc"]
            |> Enum.map(&create_completion_item(&1, "class"))

          true ->
            []
        end

      :attribute ->
        ["id", "arn", "name", "tags", "apply"]
        |> Enum.map(&create_completion_item(&1, "field"))

      _ ->
        ["export", "Output", "Config", "ResourceOptions"]
        |> Enum.map(&create_completion_item(&1, "keyword"))
    end
  end

  # Generic IaC completions
  defp complete_generic(context) do
    case context.trigger do
      :none ->
        ["resource", "variable", "output", "provider"]
        |> Enum.map(&create_completion_item(&1, "keyword"))

      _ ->
        []
    end
  end

  # Create LSP completion item
  defp create_completion_item(label, kind_str) do
    kind = case kind_str do
      "class" -> 7       # Class
      "interface" -> 8   # Interface
      "module" -> 9      # Module
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
