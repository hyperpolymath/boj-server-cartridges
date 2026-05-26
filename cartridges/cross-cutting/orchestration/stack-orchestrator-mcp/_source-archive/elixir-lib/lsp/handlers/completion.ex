# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyOrchestrator.LSP.Handlers.Completion do
  @moduledoc """
  Completion provider for stack.compose.toml files.
  """

  @component_types [
    %{label: "cloud.provision", detail: "Provision cloud infrastructure", kind: 3},
    %{label: "database.provision", detail: "Provision database", kind: 3},
    %{label: "container.build", detail: "Build container image", kind: 3},
    %{label: "kubernetes.deploy", detail: "Deploy to Kubernetes", kind: 3},
    %{label: "observability.setup", detail: "Setup monitoring", kind: 3},
    %{label: "secrets.create", detail: "Create secrets", kind: 3},
    %{label: "git.create", detail: "Create git repository", kind: 3},
    %{label: "queue.setup", detail: "Setup message queue", kind: 3},
    %{label: "ssg.generate", detail: "Generate static site", kind: 3},
    %{label: "iac.apply", detail: "Apply IaC configuration", kind: 3},
    %{label: "browser.automate", detail: "Browser automation", kind: 3},
    %{label: "proof.verify", detail: "Verify formal proof", kind: 3}
  ]

  @lsp_servers [
    %{label: "poly-cloud", detail: "AWS, GCP, Azure, DigitalOcean", kind: 9},
    %{label: "poly-db", detail: "PostgreSQL, MongoDB, Redis, etc.", kind: 9},
    %{label: "poly-container", detail: "nerdctl, podman, docker", kind: 9},
    %{label: "poly-k8s", detail: "kubectl, Helm, Kustomize", kind: 9},
    %{label: "poly-observability", detail: "Prometheus, Grafana, Loki", kind: 9},
    %{label: "poly-secret", detail: "Vault, SOPS", kind: 9},
    %{label: "poly-git", detail: "GitHub, GitLab, Gitea", kind: 9},
    %{label: "poly-queue", detail: "Redis Streams, RabbitMQ, NATS", kind: 9},
    %{label: "poly-ssg", detail: "Zola, Hugo, Jekyll, etc.", kind: 9},
    %{label: "poly-iac", detail: "OpenTofu, Pulumi", kind: 9},
    %{label: "claude-firefox", detail: "Firefox Marionette", kind: 9},
    %{label: "poly-proof", detail: "Coq, Lean, Isabelle, Agda", kind: 9}
  ]

  @security_policies [
    %{label: "no-root-containers", detail: "Containers run as non-root", kind: 14},
    %{label: "encrypted-secrets", detail: "All secrets encrypted at rest", kind: 14},
    %{label: "network-isolation", detail: "Components network-isolated", kind: 14},
    %{label: "audit-logging", detail: "All actions logged", kind: 14},
    %{label: "least-privilege", detail: "Minimal permissions", kind: 14}
  ]

  def provide(text, _position) do
    # Simple context-aware completion
    # In production, would parse position and provide context-specific suggestions

    cond do
      String.contains?(text, "type =") ->
        @component_types

      String.contains?(text, "lsp_server =") ->
        @lsp_servers

      String.contains?(text, "policies =") ->
        @security_policies

      true ->
        # Default: all completion types
        @component_types ++ @lsp_servers ++ @security_policies
    end
  end
end
