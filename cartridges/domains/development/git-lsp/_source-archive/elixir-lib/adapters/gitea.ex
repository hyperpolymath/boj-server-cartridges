# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyGit.Adapters.Gitea do
  @moduledoc """
  Gitea adapter using the `tea` CLI tool.

  Requires: tea CLI (https://gitea.com/gitea/tea)
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
      # Gitea instances can have custom domains, check for common patterns
      has_gitea = String.contains?(content, "gitea") or
                  String.contains?(content, "tea.xyz") or
                  String.contains?(content, "codeberg.org")
      {:ok, has_gitea}
    else
      {:ok, false}
    end
  end

  @impl PolyGit.Adapters.Behaviour
  def create_repo(org, name, opts) do
    description = Keyword.get(opts, :description, "")
    private = if Keyword.get(opts, :private, false), do: "--private", else: ""

    args = [
      "repos", "create",
      "--name", name,
      "--owner", org,
      "--description", description
    ]

    args = if private != "", do: args ++ [private], else: args

    case System.cmd("tea", args, stderr_to_stdout: true) do
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

    args = [
      "pulls", "create",
      "--repo", "#{org}/#{repo}",
      "--title", title,
      "--description", body,
      "--head", head,
      "--base", base
    ]

    case System.cmd("tea", args, stderr_to_stdout: true) do
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
      "issues", "create",
      "--repo", "#{org}/#{repo}",
      "--title", title,
      "--body", body
    ]

    args = if Enum.empty?(labels) do
      args
    else
      args ++ Enum.flat_map(labels, fn label -> ["--label", label] end)
    end

    case System.cmd("tea", args, stderr_to_stdout: true) do
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
      "pulls", "list",
      "--repo", "#{org}/#{repo}",
      "--state", state,
      "--limit", to_string(limit),
      "--output", "simple"
    ]

    case System.cmd("tea", args, stderr_to_stdout: true) do
      {output, 0} ->
        # Parse tea output
        prs = output
          |> String.split("\n", trim: true)
          |> Enum.drop(1)  # Skip header line
          |> Enum.map(&parse_pr_line/1)
          |> Enum.reject(&is_nil/1)
        {:ok, prs}
      {error, _} -> {:error, error}
    end
  end

  @impl PolyGit.Adapters.Behaviour
  def merge_pr(org, repo, pr_number, opts) do
    merge_method = case Keyword.get(opts, :merge_method, :merge) do
      :merge -> "merge"
      :squash -> "squash"
      :rebase -> "rebase"
    end

    args = [
      "pulls", "merge",
      "--repo", "#{org}/#{repo}",
      to_string(pr_number),
      "--style", merge_method
    ]

    case System.cmd("tea", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, %{result: String.trim(output)}}
      {error, _} -> {:error, error}
    end
  end

  @impl PolyGit.Adapters.Behaviour
  def version do
    case System.cmd("tea", ["--version"], stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {error, _} -> {:error, error}
    end
  end

  @impl PolyGit.Adapters.Behaviour
  def metadata do
    %{
      name: "Gitea",
      cli_tool: "tea",
      description: "Gitea CLI adapter for repository and PR management",
      forge_url: "https://gitea.com",
      supports_api: true
    }
  end

  # Server callbacks

  @impl GenServer
  def init(state) do
    {:ok, state}
  end

  # Private helpers

  defp parse_pr_line(line) do
    # Parse format: #123  Title  (open)  branch -> base
    case String.split(line, ~r/\s+/, trim: true) do
      ["#" <> number | rest] ->
        # This is a simplified parser; actual tea output may vary
        %{
          number: String.to_integer(number),
          title: Enum.join(Enum.take(rest, -4), " "),
          state: "open"
        }
      _ -> nil
    end
  end
end
