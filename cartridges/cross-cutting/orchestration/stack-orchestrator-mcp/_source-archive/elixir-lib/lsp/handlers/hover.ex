# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyOrchestrator.LSP.Handlers.Hover do
  @moduledoc """
  Hover documentation provider for stack.compose.toml.
  """

  @component_docs %{
    "cloud.provision" => """
    **Cloud Infrastructure Provisioning**

    Provisions cloud infrastructure (VPC, subnets, networks).

    **Handled by**: poly-cloud-lsp
    **Adapters**: AWS, GCP, Azure, DigitalOcean
    **Typical duration**: 2-5 minutes
    """,
    "database.provision" => """
    **Database Provisioning**

    Provisions a managed or self-hosted database.

    **Handled by**: poly-db-lsp
    **Adapters**: PostgreSQL, MongoDB, Redis, Neo4j, MySQL, SQLite, etc.
    **Typical duration**: 3-10 minutes
    """,
    "container.build" => """
    **Container Build**

    Builds a container image from Dockerfile.

    **Handled by**: poly-container-lsp
    **Adapters**: nerdctl, podman, docker
    **Typical duration**: 1-5 minutes
    """,
    "kubernetes.deploy" => """
    **Kubernetes Deployment**

    Deploys containers to Kubernetes cluster.

    **Handled by**: poly-k8s-lsp
    **Adapters**: kubectl, Helm, Kustomize
    **Typical duration**: 1-3 minutes
    """
  }

  @lsp_docs %{
    "poly-cloud" => """
    **poly-cloud-lsp**

    Multi-cloud infrastructure management.

    **Adapters**: AWS, GCP, Azure, DigitalOcean
    **Repository**: https://github.com/hyperpolymath/poly-cloud-lsp
    """,
    "poly-db" => """
    **poly-db-lsp**

    Database management for 21+ database systems.

    **Adapters**: PostgreSQL, MongoDB, Redis, Neo4j, MySQL, SQLite, and 15 more
    **Repository**: https://github.com/hyperpolymath/poly-db-lsp
    """
  }

  def provide(text, _position) do
    # Simple keyword-based hover (in production, would parse position precisely)

    cond do
      String.contains?(text, "cloud.provision") ->
        %{kind: "markdown", value: @component_docs["cloud.provision"]}

      String.contains?(text, "database.provision") ->
        %{kind: "markdown", value: @component_docs["database.provision"]}

      String.contains?(text, "container.build") ->
        %{kind: "markdown", value: @component_docs["container.build"]}

      String.contains?(text, "kubernetes.deploy") ->
        %{kind: "markdown", value: @component_docs["kubernetes.deploy"]}

      String.contains?(text, "poly-cloud") ->
        %{kind: "markdown", value: @lsp_docs["poly-cloud"]}

      String.contains?(text, "poly-db") ->
        %{kind: "markdown", value: @lsp_docs["poly-db"]}

      true ->
        nil
    end
  end
end
