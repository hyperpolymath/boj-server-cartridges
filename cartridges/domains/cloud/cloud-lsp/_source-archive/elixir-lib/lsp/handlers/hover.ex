# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyCloud.LSP.Handlers.Hover do
  @moduledoc """
  Provides hover documentation for cloud resources and configurations.
  """

  def handle(params, assigns) do
    uri = get_in(params, ["textDocument", "uri"])
    position = params["position"]

    doc = get_in(assigns, [:documents, uri])
    text = if doc, do: doc.text, else: ""

    word = get_word_at_position(text, position["line"], position["character"])

    if word do
      docs = case assigns[:detected_provider] do
        :aws -> get_aws_docs(word)
        :gcp -> get_gcp_docs(word)
        :azure -> get_azure_docs(word)
        :digitalocean -> get_digitalocean_docs(word)
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

  defp get_word_at_position(text, line, character) do
    lines = String.split(text, "\n")
    current_line = Enum.at(lines, line, "")

    before = String.slice(current_line, 0, character) |> String.reverse()
    after_text = String.slice(current_line, character, String.length(current_line))

    start = Regex.run(~r/^[a-zA-Z0-9_-]*/, before) |> List.first() |> String.reverse()
    end_part = Regex.run(~r/^[a-zA-Z0-9_-]*/, after_text) |> List.first()

    word = start <> end_part
    if String.length(word) > 0, do: word, else: nil
  end

  defp get_aws_docs(word) do
    docs = %{
      "EC2" => "**EC2** - Elastic Compute Cloud\n\nVirtual servers in the cloud",
      "S3" => "**S3** - Simple Storage Service\n\nScalable object storage",
      "Lambda" => "**Lambda** - Serverless compute service\n\nRun code without managing servers",
      "RDS" => "**RDS** - Relational Database Service\n\nManaged database service",
      "us-east-1" => "**us-east-1** - US East (N. Virginia)",
      "us-west-2" => "**us-west-2** - US West (Oregon)"
    }
    Map.get(docs, word)
  end

  defp get_gcp_docs(word) do
    docs = %{
      "Compute Engine" => "**Compute Engine** - Virtual machines running in Google's data centers",
      "Cloud Storage" => "**Cloud Storage** - Object storage for companies of all sizes",
      "Cloud Functions" => "**Cloud Functions** - Event-driven serverless compute platform"
    }
    Map.get(docs, word)
  end

  defp get_azure_docs(word) do
    docs = %{
      "Virtual Machines" => "**Virtual Machines** - On-demand scalable computing resources",
      "Blob Storage" => "**Blob Storage** - Massively scalable object storage",
      "Functions" => "**Functions** - Event-driven serverless compute"
    }
    Map.get(docs, word)
  end

  defp get_digitalocean_docs(word) do
    docs = %{
      "Droplets" => "**Droplets** - Scalable virtual machines",
      "Spaces" => "**Spaces** - Object storage service",
      "Functions" => "**Functions** - Serverless compute platform"
    }
    Map.get(docs, word)
  end

  defp get_generic_docs(word) do
    docs = %{
      "provider" => "**provider** - Cloud service provider (aws, gcp, azure, digitalocean)",
      "region" => "**region** - Geographic region for resources",
      "instance_type" => "**instance_type** - Size/type of compute instance"
    }
    Map.get(docs, word)
  end
end
