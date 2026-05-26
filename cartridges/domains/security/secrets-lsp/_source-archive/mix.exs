# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

defmodule PolySecret.LSP.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/hyperpolymath/poly-secret-lsp"

  def project do
    [
      app: :poly_secret_lsp,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),

      # Package info
      name: "PolySecret LSP",
      description: "Language Server Protocol implementation for secrets management (HashiCorp Vault, Mozilla SOPS)",
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
      extra_applications: [:logger, :crypto],
      mod: {PolySecret.LSP.Application, []}
    ]
  end

  defp deps do
    [
      # LSP Framework
      {:gen_lsp, "~> 0.10"},

      # JSON parsing
      {:jason, "~> 1.4"},

      # YAML parsing (for SOPS files)
      {:yaml_elixir, "~> 2.11"},

      # YAML serialization (for SOPS files)
      {:ymlr, "~> 5.1"},

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
      name: "poly_secret_lsp",
      files: ~w(lib .formatter.exs mix.exs README.adoc LICENSE CHANGELOG.md),
      licenses: ["PMPL-1.0-or-later"],
      links: %{
        "GitHub" => @source_url
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.adoc", "CHANGELOG.md"],
      source_ref: "v#{@version}",
      source_url: @source_url,
      authors: ["Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>"]
    ]
  end
end
