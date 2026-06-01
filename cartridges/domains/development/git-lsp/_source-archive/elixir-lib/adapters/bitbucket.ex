# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyGit.Adapters.Bitbucket do
  @moduledoc """
  Bitbucket adapter using the `bb` CLI tool.

  Requires: bb CLI (Bitbucket CLI)
  Note: Bitbucket doesn't have an official CLI, so this uses community tool or API calls
  """

  use GenServer
  @behaviour PolyGit.Adapters.Behaviour

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl PolyGit.Adapters.Behaviour
  def detect(project_path) do
    git_config = Path.join([project_path, ".git", "config"])

    if File.exists?(git_config) do
      content = File.read!(git_config)
      has_bitbucket = String.contains?(content, "bitbucket.org")
      {:ok, has_bitbucket}
    else
      {:ok, false}
    end
  end

  @impl PolyGit.Adapters.Behaviour
  def create_repo(org, name, opts) do
    # Note: This is a placeholder implementation
    # Bitbucket requires API calls or third-party CLI
    description = Keyword.get(opts, :description, "")
    private = Keyword.get(opts, :private, false)

    # Using git and API directly would be required here
    {:error, "Bitbucket adapter requires API implementation"}
  end

  @impl PolyGit.Adapters.Behaviour
  def create_pr(org, repo, opts) do
    title = Keyword.fetch!(opts, :title)
    body = Keyword.get(opts, :body, "")
    head = Keyword.fetch!(opts, :head)
    base = Keyword.get(opts, :base, "main")

    # Placeholder - would use Bitbucket API via Req
    {:error, "Bitbucket adapter requires API implementation"}
  end

  @impl PolyGit.Adapters.Behaviour
  def create_issue(org, repo, opts) do
    title = Keyword.fetch!(opts, :title)
    body = Keyword.get(opts, :body, "")

    # Placeholder - would use Bitbucket API via Req
    {:error, "Bitbucket adapter requires API implementation"}
  end

  @impl PolyGit.Adapters.Behaviour
  def list_prs(org, repo, opts) do
    # Placeholder - would use Bitbucket API via Req
    {:error, "Bitbucket adapter requires API implementation"}
  end

  @impl PolyGit.Adapters.Behaviour
  def merge_pr(org, repo, pr_number, opts) do
    # Placeholder - would use Bitbucket API via Req
    {:error, "Bitbucket adapter requires API implementation"}
  end

  @impl PolyGit.Adapters.Behaviour
  def version do
    {:ok, "Bitbucket API adapter v0.1.0"}
  end

  @impl PolyGit.Adapters.Behaviour
  def metadata do
    %{
      name: "Bitbucket",
      cli_tool: "api",
      description: "Bitbucket API adapter for repository and PR management (requires API token)",
      forge_url: "https://bitbucket.org",
      supports_api: true
    }
  end

  # Server callbacks

  @impl GenServer
  def init(state) do
    {:ok, state}
  end
end
