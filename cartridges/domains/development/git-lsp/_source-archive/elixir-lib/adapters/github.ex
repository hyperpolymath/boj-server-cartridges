# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyGit.Adapters.GitHub do
  @moduledoc """
  GitHub adapter using the `gh` CLI tool.

  Requires: gh CLI (https://cli.github.com/)
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
      {:ok, String.contains?(content, "github.com")}
    else
      {:ok, false}
    end
  end

  @impl PolyGit.Adapters.Behaviour
  def create_repo(org, name, opts) do
    description = Keyword.get(opts, :description, "")
    private = if Keyword.get(opts, :private, false), do: "--private", else: "--public"

    args = [
      "repo", "create", "#{org}/#{name}",
      private,
      "--description", description
    ]

    case System.cmd("gh", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, %{repo: "#{org}/#{name}", output: output}}
      {error, _} -> {:error, error}
    end
  end

  @impl PolyGit.Adapters.Behaviour
  def create_pr(org, repo, opts) do
    title = Keyword.fetch!(opts, :title)
    body = Keyword.get(opts, :body, "")
    head = Keyword.fetch!(opts, :head)
    base = Keyword.get(opts, :base, "main")
    draft = if Keyword.get(opts, :draft, false), do: ["--draft"], else: []

    args = [
      "pr", "create",
      "--repo", "#{org}/#{repo}",
      "--title", title,
      "--body", body,
      "--head", head,
      "--base", base
    ] ++ draft

    case System.cmd("gh", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, %{pr_url: String.trim(output)}}
      {error, _} -> {:error, error}
    end
  end

  @impl PolyGit.Adapters.Behaviour
  def create_issue(org, repo, opts) do
    title = Keyword.fetch!(opts, :title)
    body = Keyword.get(opts, :body, "")
    labels = Keyword.get(opts, :labels, [])

    args = [
      "issue", "create",
      "--repo", "#{org}/#{repo}",
      "--title", title,
      "--body", body
    ]

    args = if Enum.empty?(labels) do
      args
    else
      args ++ ["--label", Enum.join(labels, ",")]
    end

    case System.cmd("gh", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, %{issue_url: String.trim(output)}}
      {error, _} -> {:error, error}
    end
  end

  @impl PolyGit.Adapters.Behaviour
  def list_prs(org, repo, opts) do
    state = case Keyword.get(opts, :state, :open) do
      :open -> "open"
      :closed -> "closed"
      :all -> "all"
    end
    limit = Keyword.get(opts, :limit, 30)

    args = [
      "pr", "list",
      "--repo", "#{org}/#{repo}",
      "--state", state,
      "--limit", to_string(limit),
      "--json", "number,title,url,state,headRefName,baseRefName"
    ]

    case System.cmd("gh", args, stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, prs} -> {:ok, prs}
          {:error, _} -> {:error, "Failed to parse PR list"}
        end
      {error, _} -> {:error, error}
    end
  end

  @impl PolyGit.Adapters.Behaviour
  def merge_pr(org, repo, pr_number, opts) do
    merge_method = case Keyword.get(opts, :merge_method, :merge) do
      :merge -> "--merge"
      :squash -> "--squash"
      :rebase -> "--rebase"
    end

    args = [
      "pr", "merge",
      "--repo", "#{org}/#{repo}",
      to_string(pr_number),
      merge_method
    ]

    case System.cmd("gh", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, %{result: String.trim(output)}}
      {error, _} -> {:error, error}
    end
  end

  @impl PolyGit.Adapters.Behaviour
  def version do
    case System.cmd("gh", ["--version"], stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {error, _} -> {:error, error}
    end
  end

  @impl PolyGit.Adapters.Behaviour
  def metadata do
    %{
      name: "GitHub",
      cli_tool: "gh",
      description: "GitHub CLI adapter for repository and PR management",
      forge_url: "https://github.com",
      supports_api: true
    }
  end

  # Server callbacks

  @impl GenServer
  def init(state) do
    {:ok, state}
  end
end
