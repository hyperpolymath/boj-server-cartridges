# poly-ssg-lsp

> Language Server Protocol implementation for 60+ static site generators

[![License: PMPL-1.0](https://img.shields.io/badge/License-PMPL--1.0-blue.svg)](https://github.com/hyperpolymath/palimpsest-license)
[![Elixir 1.17+](https://img.shields.io/badge/elixir-1.17+-purple.svg)](https://elixir-lang.org/)

## Overview

**poly-ssg-lsp** provides IDE integration for static site generators across 60+ languages and frameworks. Built with Elixir's BEAM VM, each SSG adapter runs as an isolated process with automatic fault recovery.

## Features

- 🔄 **Auto-detection**: Detects SSG type from project files
- ✨ **Auto-completion**: Template syntax, frontmatter, shortcodes
- 🔍 **Diagnostics**: Build errors, configuration issues
- 📚 **Hover docs**: SSG-specific documentation
- ⚡ **Commands**: Build, serve, clean directly from editor
- 🛡️ **Fault isolation**: Crash in one adapter doesn't affect others

## Installation

\`\`\`bash
git clone https://github.com/hyperpolymath/poly-ssg-lsp
cd poly-ssg-lsp
mix deps.get
mix compile
\`\`\`

## License

PMPL-1.0-or-later
