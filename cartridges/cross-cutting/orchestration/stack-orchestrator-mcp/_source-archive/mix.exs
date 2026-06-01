# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolyOrchestrator.LSP.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/hyperpolymath/poly-orchestrator-lsp"

  def project do
    [
      app: :poly_orchestrator_lsp,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),

      # Package info
      name: "PolyOrchestrator LSP",
      description: "Orchestration layer for 12 hyperpolymath LSP servers with stapeln integration",
      package: package(),
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs(),

      # Testing
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],

      # Dialyzer
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit],
        plt_core_path: "priv/plts",
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {PolyOrchestrator.LSP.Application, []}
    ]
  end

  defp deps do
    [
      # LSP Framework
      {:gen_lsp, "~> 0.10"},

      # JSON/TOML parsing
      {:jason, "~> 1.4"},
      {:toml, "~> 0.7"},

      # Dependency graph analysis
      {:libgraph, "~> 0.16"},

      # HTTP client for LSP-to-LSP communication and VeriSimDB
      {:tesla, "~> 1.9"},
      {:hackney, "~> 1.20"},

      # miniKanren integration (for security policy validation)
      # Note: We'll create a NIF wrapper for the Scheme miniKanren
      # or use Elixir-native logic programming library as alternative

      # Testing & quality
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:mox, "~> 1.1", only: :test}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "compile"],
      quality: ["format --check-formatted", "credo --strict", "dialyzer"],
      "test.all": ["test", "dialyzer", "credo"]
    ]
  end

  defp package do
    [
      name: "poly_orchestrator_lsp",
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md),
      licenses: ["MPL-2.0"],
      links: %{
        "GitHub" => @source_url,
        "stapeln" => "https://github.com/hyperpolymath/stapeln",
        "poly-ssg-lsp" => "https://github.com/hyperpolymath/poly-ssg-lsp"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      source_ref: "v#{@version}",
      source_url: @source_url,
      authors: ["Jonathan D.A. Jewell"]
    ]
  end
end
