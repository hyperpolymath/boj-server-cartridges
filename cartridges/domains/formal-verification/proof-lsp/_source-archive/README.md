# poly-proof-lsp

> Production-ready Language Server Protocol implementation for proof assistants

[![Production Ready](https://img.shields.io/badge/status-production--ready-brightgreen.svg)](https://github.com/hyperpolymath/poly-proof-lsp)
[![Version: 1.0.0](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/hyperpolymath/poly-proof-lsp/releases)
[![License: PMPL-1.0](https://img.shields.io/badge/License-PMPL--1.0-blue.svg)](https://github.com/hyperpolymath/palimpsest-license)
[![Elixir 1.17+](https://img.shields.io/badge/elixir-1.17+-purple.svg)](https://elixir-lang.org/)

## Overview

**poly-proof-lsp** provides IDE integration for formal verification tools including Coq, Lean, Isabelle, and Agda. Built with Elixir's BEAM VM, each proof assistant adapter runs as an isolated process with automatic fault recovery.

## Features

- 🔍 **Auto-detection**: Detects proof assistant from project files
- ✅ **Proof checking**: Real-time validation with coqc, lean, isabelle, agda
- 🎯 **Goal display**: Show current proof goals and hypotheses
- ✨ **Tactic completion**: Auto-complete tactics and proof commands
- 📚 **Theorem search**: Search standard libraries for relevant theorems
- 📖 **Hover docs**: Display proof state and type information
- ⚡ **Commands**: Check proofs, show goals, apply tactics directly from editor
- 🛡️ **Fault isolation**: Crash in one adapter doesn't affect others

## Supported Proof Assistants

| Proof Assistant | File Extensions | Interactive Mode | Status |
|----------------|-----------------|------------------|--------|
| **Coq** | `.v` | coqtop | ✅ Production |
| **Lean** | `.lean` | lean --server | ✅ Production |
| **Isabelle** | `.thy` | PIDE | ✅ Production |
| **Agda** | `.agda`, `.lagda`, `.lagda.md` | agda --interaction | ✅ Production |

## Installation

```bash
git clone https://github.com/hyperpolymath/poly-proof-lsp
cd poly-proof-lsp
mix deps.get
mix compile
```

## Usage

### Standalone

```bash
mix run --no-halt
```

### With VSCode

1. Install the extension:
   ```bash
   cd vscode-extension
   npm install
   npm run package
   code --install-extension *.vsix
   ```

2. Configure in `settings.json`:
   ```json
   {
     "polyProof.enable": true,
     "polyProof.serverPath": "/path/to/poly-proof-lsp"
   }
   ```

See [USAGE.md](USAGE.md) for detailed configuration options.

### With Neovim

```lua
require('lspconfig').poly_proof_lsp.setup{
  cmd = {'/path/to/poly-proof-lsp/bin/poly-proof-lsp'},
  filetypes = {'coq', 'lean', 'isabelle', 'agda'},
}
```

## Development

```bash
# Setup
just setup

# Run tests
just test

# Check code quality
just quality

# Format code
just format

# Generate docs
just docs
```

## Architecture

Each proof assistant runs as an isolated GenServer under a supervision tree:

```
PolyProof.LSP.Supervisor
├── PolyProof.Adapters.Supervisor
│   ├── PolyProof.Adapters.Coq (GenServer)
│   ├── PolyProof.Adapters.Lean (GenServer)
│   ├── PolyProof.Adapters.Isabelle (GenServer)
│   └── PolyProof.Adapters.Agda (GenServer)
└── PolyProof.LSP.Server
```

Crashes in one adapter automatically restart without affecting others. Multiple proofs can be checked concurrently.

## Troubleshooting

### Server Not Starting

- Check Elixir/OTP versions: `elixir --version`
- Verify dependencies: `mix deps.get`
- Check logs: `tail -f log/poly_proof.log`

### LSP Not Connecting

- Verify server is running: `ps aux | grep poly_proof`
- Check LSP client logs in your editor
- Ensure correct file types are configured

### Performance Issues

- Monitor with Observer: `iex -S mix`, then `:observer.start()`
- Check adapter health via `health_check` command
- Review adapter-specific logs

See [USAGE.md](USAGE.md) for more detailed troubleshooting steps.

## Related Projects

- [poly-ssg-lsp](https://github.com/hyperpolymath/poly-ssg-lsp) - LSP for static site generators
- [poly-observability-lsp](https://github.com/hyperpolymath/poly-observability-lsp) - LSP for observability tools

## License

PMPL-1.0-or-later

## Author

Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
