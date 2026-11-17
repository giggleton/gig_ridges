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
      description: "Ridgeline plots for Giggly: ridgelines and density ridges.",
      package: [licenses: ["MIT"]]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  # Giggly is taken by path from the worktree that holds its plugin API until that API is
  # released; a Hex release of this package waits for Giggly's.
  defp deps do
    [
      {:giggly, path: "/home/srowley/repos/giggly/.claude/worktrees/next-increment-cf41fe"},
      {:nx, "~> 1.0"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
