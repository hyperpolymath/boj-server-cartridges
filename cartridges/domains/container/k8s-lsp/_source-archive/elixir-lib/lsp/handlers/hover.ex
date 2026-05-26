# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyK8s.LSP.Handlers.Hover do
  @moduledoc """
  Hover documentation handler for Kubernetes manifests.

  Provides documentation for:
  - Kubernetes resource types with links to docs
  - Field descriptions from API schema
  - Common Kubernetes concepts
  """

  def handle(params, assigns) do
    uri = get_in(params, ["textDocument", "uri"])
    position = params["position"]

    doc = get_in(assigns, [:documents, uri])
    text = if doc, do: doc.text, else: ""

    word = get_word_at_position(text, position["line"], position["character"])

    if word do
      docs = get_k8s_docs(word)

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

  defp get_k8s_docs(word) do
    docs = %{
      "Pod" => "**Pod** - The smallest deployable units of computing that you can create and manage in Kubernetes.\n\n[Documentation](https://kubernetes.io/docs/concepts/workloads/pods/)",
      "Deployment" => "**Deployment** - Provides declarative updates for Pods and ReplicaSets.\n\n[Documentation](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)",
      "Service" => "**Service** - An abstract way to expose an application running on a set of Pods as a network service.\n\n[Documentation](https://kubernetes.io/docs/concepts/services-networking/service/)",
      "ConfigMap" => "**ConfigMap** - An API object used to store non-confidential data in key-value pairs.\n\n[Documentation](https://kubernetes.io/docs/concepts/configuration/configmap/)",
      "Secret" => "**Secret** - An object that contains a small amount of sensitive data such as a password, a token, or a key.\n\n[Documentation](https://kubernetes.io/docs/concepts/configuration/secret/)",
      "Namespace" => "**Namespace** - Provides a mechanism for isolating groups of resources within a single cluster.\n\n[Documentation](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/)",
      "Ingress" => "**Ingress** - Manages external access to services in a cluster, typically HTTP.\n\n[Documentation](https://kubernetes.io/docs/concepts/services-networking/ingress/)",
      "StatefulSet" => "**StatefulSet** - Manages stateful applications with unique network identifiers and persistent storage.\n\n[Documentation](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)",
      "DaemonSet" => "**DaemonSet** - Ensures that all (or some) Nodes run a copy of a Pod.\n\n[Documentation](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/)",
      "Job" => "**Job** - Creates one or more Pods and ensures that a specified number of them successfully terminate.\n\n[Documentation](https://kubernetes.io/docs/concepts/workloads/controllers/job/)",
      "CronJob" => "**CronJob** - Creates Jobs on a repeating schedule.\n\n[Documentation](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/)",
      "apiVersion" => "**apiVersion** - Specifies which version of the Kubernetes API you're using to create this object.",
      "kind" => "**kind** - The type of Kubernetes resource (Pod, Deployment, Service, etc.).",
      "metadata" => "**metadata** - Data that helps uniquely identify the object (name, namespace, labels, annotations).",
      "spec" => "**spec** - The desired state of the object.",
      "replicas" => "**replicas** - The number of desired pod replicas.",
      "selector" => "**selector** - Used to identify a set of objects based on their labels.",
      "containers" => "**containers** - List of containers belonging to the pod.",
      "image" => "**image** - Container image name.",
      "ports" => "**ports** - List of ports to expose from the container."
    }

    Map.get(docs, word)
  end
end
