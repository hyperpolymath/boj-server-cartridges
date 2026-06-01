# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyGit.Adapters.GitLab do
  @moduledoc """
  GitLab adapter using the `glab` CLI tool.

  Requires: glab CLI (https://gitlab.com/gitlab-org/cli)
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
      {:ok, String.contains?(content, "gitlab.com")}
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

    case System.cmd("glab", args, stderr_to_stdout: true) do
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
      "mr", "create",
      "--repo", "#{org}/#{repo}",
      "--title", title,
      "--description", body,
      "--source-branch", head,
      "--target-branch", base
    ] ++ draft

    case System.cmd("glab", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, %{mr_url: String.trim(output)}}
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
      "--description", body
    ]

    args = if Enum.empty?(labels) do
      args
    else
      args ++ ["--label", Enum.join(labels, ",")]
    end

    case System.cmd("glab", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, %{issue_url: String.trim(output)}}
      {error, _} -> {:error, error}
    end
  end

  @impl PolyGit.Adapters.Behaviour
  def list_prs(org, repo, opts) do
    state = case Keyword.get(opts, :state, :open) do
      :open -> "opened"
      :closed -> "closed"
      :all -> "all"
    end
    limit = Keyword.get(opts, :limit, 30)

    args = [
      "mr", "list",
      "--repo", "#{org}/#{repo}",
      "--state", state,
      "--per-page", to_string(limit)
    ]

    case System.cmd("glab", args, stderr_to_stdout: true) do
      {output, 0} ->
        # Parse glab output (format: !123 Title (branch -> target))
        mrs = output
          |> String.split("\n", trim: true)
          |> Enum.map(&parse_mr_line/1)
          |> Enum.reject(&is_nil/1)
        {:ok, mrs}
      {error, _} -> {:error, error}
    end
  end

  @impl PolyGit.Adapters.Behaviour
  def merge_pr(org, repo, pr_number, opts) do
    # glab uses 'mr merge' command
    args = [
      "mr", "merge",
      "--repo", "#{org}/#{repo}",
      to_string(pr_number),
      "--yes"
    ]

    case System.cmd("glab", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, %{result: String.trim(output)}}
      {error, _} -> {:error, error}
    end
  end

  @impl PolyGit.Adapters.Behaviour
  def version do
    case System.cmd("glab", ["--version"], stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {error, _} -> {:error, error}
    end
  end

  @impl PolyGit.Adapters.Behaviour
  def metadata do
    %{
      name: "GitLab",
      cli_tool: "glab",
      description: "GitLab CLI adapter for repository and MR management",
      forge_url: "https://gitlab.com",
      supports_api: true
    }
  end

  # Server callbacks

  @impl GenServer
  def init(state) do
    {:ok, state}
  end

  # Private helpers

  defp parse_mr_line(line) do
    # Parse format: !123 Title (branch -> target)
    case Regex.run(~r/!(\d+)\s+(.+?)\s+\((.+?)\s+->\s+(.+?)\)/, line) do
      [_, number, title, head, base] ->
        %{
          number: String.to_integer(number),
          title: title,
          headRefName: head,
          baseRefName: base,
          state: "opened"
        }
      _ -> nil
    end
  end
end
