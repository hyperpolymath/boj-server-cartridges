# poly-git-lsp

> Language Server Protocol implementation for Git forge management (GitHub, GitLab, Gitea, Bitbucket)

[![License: MPL-2.0](https://img.shields.io/badge/License-MPL--2.0-brightgreen.svg)](https://www.mozilla.org/en-US/MPL/2.0/)
[![Elixir 1.17+](https://img.shields.io/badge/elixir-1.17+-purple.svg)](https://elixir-lang.org/)

## Overview

**poly-git-lsp** provides IDE integration for Git forge operations across GitHub, GitLab, Gitea, and Bitbucket. Built with Elixir's BEAM VM, each forge adapter runs as an isolated process with automatic fault recovery.

## Features

- 🔄 **Auto-detection**: Detects Git forge from .git/config
- 📦 **Repository management**: Create repos, configure settings
- 🔀 **Pull/Merge requests**: Create, list, merge PRs/MRs
- 🐛 **Issue tracking**: Create and manage issues
- ⚡ **Commands**: Execute forge operations directly from editor
- 🛡️ **Fault isolation**: Crash in one adapter doesn't affect others

## Supported Forges

| Forge | CLI Tool | Status |
|-------|----------|--------|
| GitHub | `gh` | ✅ Implemented |
| GitLab | `glab` | ✅ Implemented |
| Gitea | `tea` | ✅ Implemented |
| Bitbucket | API | 🚧 Placeholder |

## Installation

```bash
git clone https://github.com/hyperpolymath/poly-git-lsp
cd poly-git-lsp
mix deps.get
mix compile
```

## Prerequisites

Install the CLI tools for your Git forge:

- **GitHub**: [gh CLI](https://cli.github.com/)
- **GitLab**: [glab CLI](https://gitlab.com/gitlab-org/cli)
- **Gitea**: [tea CLI](https://gitea.com/gitea/tea)
- **Bitbucket**: API token (no official CLI)

## Usage

### VSCode Extension

Coming soon. Will provide commands like:

- `Poly-Git: Detect Forge`
- `Poly-Git: Create Repository`
- `Poly-Git: Create Pull Request`
- `Poly-Git: List Pull Requests`
- `Poly-Git: Merge Pull Request`

### Direct Usage

```elixir
# Detect which forge is used
PolyGit.LSP.detect_forge("/path/to/project")
# => [PolyGit.Adapters.GitHub]

# Create a PR
PolyGit.Adapters.GitHub.create_pr("hyperpolymath", "poly-git-lsp",
  title: "Add new feature",
  body: "This PR adds...",
  head: "feature-branch",
  base: "main"
)
```

## Architecture

- **Adapters**: Each forge (GitHub, GitLab, etc.) is a separate GenServer
- **Supervision**: One-for-one supervision strategy - crashed adapters restart independently
- **LSP Protocol**: Uses GenLSP for language server implementation
- **CLI Tools**: Wraps official CLI tools (gh, glab, tea) for reliability

## Development

```bash
# Run tests
mix test

# Type checking
mix dialyzer

# Linting
mix credo --strict

# Format code
mix format
```

## License

MPL-2.0

## Author

Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
