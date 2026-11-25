defmodule GigRidges.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/giggleton/gig_ridges"

  def project do
    [
      app: :gig_ridges,
      version: @version,
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      description: "Ridgeline plots for Giggly: ridgelines and density ridges.",
      package: [licenses: ["MIT"], links: %{"GitHub" => @source_url}],
      source_url: @source_url,
      docs: [main: "GigRidges", source_ref: "v#{@version}"]
    ]
  end

  # `mix quality` runs in test, the environment its `mix test` step needs.
  def cli do
    [preferred_envs: [quality: :test]]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  # Giggly holds the plugin API this package builds on. Scales, the colours Giggly reads, is
  # taken for its documented `Scales.ColorOperations.parse/1`, which checks a colour a gig_ridges
  # option sets as Giggly checks its own.
  defp deps do
    [
      {:giggly, "~> 0.2.0"},
      {:scales, "~> 0.2.0"},
      {:nx, "~> 1.0"},
      {:gig_datasets, "~> 0.1.0", only: [:dev, :test]},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      # Pinned exactly: the mutation-testing skill's runner builds mutants through muex's library
      # internals, checked against this version, so an upgrade re-checks the runner.
      {:muex, "== 0.11.3", only: [:dev, :test], runtime: false}
    ]
  end

  # The commit gate: run bare before every commit; it stops at the first step that fails.
  defp aliases do
    [
      quality: [
        "format --check-formatted",
        "hex.audit",
        "compile --warnings-as-errors",
        "test --warnings-as-errors",
        "credo --strict"
      ]
    ]
  end
end
