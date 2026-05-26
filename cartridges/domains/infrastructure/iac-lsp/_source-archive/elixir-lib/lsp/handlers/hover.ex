# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyIaC.LSP.Handlers.Hover do
  @moduledoc """
  Provides hover documentation for Infrastructure as Code syntax.

  Shows:
  - Resource type documentation
  - Attribute descriptions
  - Provider information
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
      # Get documentation based on IaC type and word
      docs = case assigns.detected_iac do
        :opentofu -> get_opentofu_docs(word)
        :pulumi -> get_pulumi_docs(word)
        _ -> get_generic_docs(word)
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

  # OpenTofu/Terraform documentation
  defp get_opentofu_docs(word) do
    docs = %{
      "resource" => "**resource** - Defines infrastructure resource\n\nUsage: `resource \"type\" \"name\" { ... }`",
      "data" => "**data** - Queries existing resources\n\nUsage: `data \"type\" \"name\" { ... }`",
      "provider" => "**provider** - Configures provider plugin\n\nUsage: `provider \"name\" { ... }`",
      "variable" => "**variable** - Defines input variable\n\nUsage: `variable \"name\" { type = string }`",
      "output" => "**output** - Exports value\n\nUsage: `output \"name\" { value = ... }`",
      "locals" => "**locals** - Define local values\n\nUsage: `locals { name = value }`",
      "module" => "**module** - Call reusable module\n\nUsage: `module \"name\" { source = \"...\" }`",
      "aws_instance" => "**aws_instance** - AWS EC2 instance\n\nRequired: `ami`, `instance_type`",
      "aws_s3_bucket" => "**aws_s3_bucket** - AWS S3 bucket\n\nRequired: `bucket`",
      "aws_vpc" => "**aws_vpc** - AWS Virtual Private Cloud\n\nRequired: `cidr_block`",
      "tags" => "**tags** - Resource tags (map)\n\nUsage: `tags = { Name = \"value\" }`",
      "cidr_block" => "**cidr_block** - IPv4 CIDR block\n\nFormat: `10.0.0.0/16`"
    }

    Map.get(docs, word)
  end

  # Pulumi documentation
  defp get_pulumi_docs(word) do
    docs = %{
      "Output" => "**Output** - Represents eventual value\n\nUsage: `new pulumi.Output(...)`",
      "Config" => "**Config** - Access configuration\n\nUsage: `const config = new pulumi.Config()`",
      "export" => "**export** - Export stack output\n\nUsage: `export const url = instance.publicIp`",
      "ResourceOptions" => "**ResourceOptions** - Resource options\n\nOptions: `dependsOn`, `protect`, `provider`",
      "Instance" => "**Instance** - Compute instance resource",
      "Bucket" => "**Bucket** - Object storage bucket",
      "apply" => "**apply** - Transform Output value\n\nUsage: `output.apply(v => ...)`"
    }

    Map.get(docs, word)
  end

  # Generic IaC documentation
  defp get_generic_docs(word) do
    docs = %{
      "resource" => "**resource** - Infrastructure resource definition",
      "variable" => "**variable** - Input parameter",
      "output" => "**output** - Exported value",
      "provider" => "**provider** - Infrastructure provider configuration"
    }

    Map.get(docs, word)
  end
end
