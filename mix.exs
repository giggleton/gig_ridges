defmodule GigRidges.MixProject do
  use Mix.Project

  @version "0.1.0"

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
      package: [licenses: ["MIT"]]
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

  # Giggly is taken by path from the worktree that holds its plugin API until that API is
  # released; a Hex release of this package waits for Giggly's. Both paths are absolute, so a git
  # worktree of this repository, which sits elsewhere, finds them.
  defp deps do
    [
      {:giggly, path: "/home/srowley/repos/giggly/.claude/worktrees/next-increment-cf41fe"},
      {:nx, "~> 1.0"},
      {:gig_datasets, path: "/home/srowley/repos/gig_datasets", only: [:dev, :test]},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
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
