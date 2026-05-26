# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyGit.Adapters.Behaviour do
  @moduledoc """
  Behaviour defining the contract for Git forge adapters.

  Each adapter implements this behaviour to provide a consistent interface
  for detecting, managing, and interacting with Git forges (GitHub, GitLab, Gitea, Bitbucket).

  ## Example

      defmodule PolyGit.Adapters.GitHub do
        use GenServer
        @behaviour PolyGit.Adapters.Behaviour

        @impl true
        def detect(project_path) do
          # Check if .git/config contains github.com
          git_config = Path.join([project_path, ".git", "config"])

          if File.exists?(git_config) do
            content = File.read!(git_config)
            {:ok, String.contains?(content, "github.com")}
          else
            {:ok, false}
          end
        end

        @impl true
        def create_repo(org, name, opts) do
          # Use gh CLI to create repo
        end
      end
  """

  @type project_path :: String.t()
  @type org :: String.t()
  @type repo_name :: String.t()
  @type pr_number :: pos_integer()
  @type issue_number :: pos_integer()
  @type opts :: keyword()
  @type result :: {:ok, map()} | {:error, String.t()}
  @type detect_result :: {:ok, boolean()} | {:error, String.t()}

  @doc """
  Detect if this Git forge is associated with the project.

  Returns `{:ok, true}` if the forge's remote URL is found in .git/config, `{:ok, false}` otherwise.
  """
  @callback detect(project_path) :: detect_result

  @doc """
  Create a new repository on the forge.

  ## Options

  - `:description` - Repository description
  - `:private` - Make repository private (boolean)
  - `:default_branch` - Default branch name (default: "main")
  - `:license` - License identifier (e.g., "PMPL-1.0-or-later")
  """
  @callback create_repo(org, repo_name, opts) :: result

  @doc """
  Create a pull request.

  ## Options

  - `:title` - PR title (required)
  - `:body` - PR description
  - `:head` - Head branch (required)
  - `:base` - Base branch (default: "main")
  - `:draft` - Create as draft PR (boolean)
  """
  @callback create_pr(org, repo_name, opts) :: result

  @doc """
  Create an issue.

  ## Options

  - `:title` - Issue title (required)
  - `:body` - Issue description
  - `:labels` - List of label strings
  - `:assignees` - List of assignee usernames
  """
  @callback create_issue(org, repo_name, opts) :: result

  @doc """
  List pull requests.

  ## Options

  - `:state` - PR state (`:open`, `:closed`, `:all`) (default: `:open`)
  - `:limit` - Maximum number of PRs to return (default: 30)
  """
  @callback list_prs(org, repo_name, opts) :: {:ok, [map()]} | {:error, String.t()}

  @doc """
  Merge a pull request.

  ## Options

  - `:merge_method` - Merge method (`:merge`, `:squash`, `:rebase`) (default: `:merge`)
  - `:commit_title` - Commit title for merge commit
  - `:commit_message` - Commit message for merge commit
  """
  @callback merge_pr(org, repo_name, pr_number, opts) :: result

  @doc """
  Get forge CLI tool version.
  """
  @callback version() :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Get forge adapter metadata (name, CLI tool, description).
  """
  @callback metadata() :: %{
              name: String.t(),
              cli_tool: String.t(),
              description: String.t(),
              forge_url: String.t(),
              supports_api: boolean()
            }
end
