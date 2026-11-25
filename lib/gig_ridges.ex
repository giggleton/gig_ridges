defmodule GigRidges do
  @moduledoc """
  Ridgeline plots for Giggly: ridges along `x`, one above each baseline, as joy plots draw them.

  `geom_ridgeline/3` draws ridges of the heights a table gives; `stat_density_ridges/3` and
  `geom_density_ridges/3` estimate each group's density along `x` and draw it as a ridge. Each
  adds a layer to a `Giggly.Plot`, through `Giggly.Plot.layer/3`, so it takes Giggly's own options
  for the marks (`fill:`, `alpha:`, `colour:`, `linewidth:`, `linetype:`, `position:`) beside its
  own, and its mistakes are refused naming it.

      iex> frame =
      ...>   GigDatasets.mpg()
      ...>   |> Giggly.Plot.new(%{x: :hwy, y: :class})
      ...>   |> GigRidges.geom_density_ridges()
      ...>   |> Giggly.layer_data()
      iex> Giggly.DataFrame.row_count(frame)
      3584
  """

  alias Giggly.Plot

  @typedoc "A layer's mapping, as `Giggly.Plot`'s layer functions take one."
  @type mapping :: %{optional(atom()) => term()}

  @doc """
  Adds a layer of ridgelines: each group a ridge along `x`, its baseline its `y` and its top
  `scale` times its `height` above it (`GigRidges.Ridgeline`), the rows drawn as they are.

  It needs `:x`, `:y` and `:height`, and takes the ridgeline's options, `scale:` and
  `min_height:`, beside Giggly's options for the marks; each may be mapped instead, giving each
  point its own, an option given beating its mapping.

      iex> frame =
      ...>   %{"x" => [1, 2, 3, 1, 2, 3], "y" => [0, 0, 0, 1, 1, 1], "h" => [0.2, 0.9, 0.3, 0.5, 0.4, 0.1]}
      ...>   |> Giggly.Plot.new(%{x: :x, y: :y, height: :h, group: :y})
      ...>   |> GigRidges.geom_ridgeline(scale: 2)
      ...>   |> Giggly.layer_data()
      iex> Giggly.DataFrame.pull(frame, :ymax)
      [0.4, 1.8, 0.6, 2.0, 1.8, 1.2]
  """
  @spec geom_ridgeline(Plot.t(), mapping() | keyword(), keyword()) :: Plot.t()
  def geom_ridgeline(plot, mapping_or_options \\ %{}, options \\ [])

  def geom_ridgeline(%Plot{} = plot, options, []) when is_list(options),
    do: geom_ridgeline(plot, %{}, options)

  def geom_ridgeline(%Plot{} = plot, mapping, options)
      when is_map(mapping) and is_list(options) do
    layer(plot, mapping, options, {:identity, GigRidges.Ridgeline}, "GigRidges.geom_ridgeline/3")
  end

  @doc """
  Adds a layer of density ridges: each group's density along `x`, estimated with one bandwidth
  each panel's groups share (`GigRidges.DensityRidges`), drawn as a ridgeline above its `y`, so the
  panel's greatest density reaches the next baseline at a `scale:` of 1.

  It needs `:x` and `:y`, `y` most often a discrete column whose values name the ridges, and takes
  the stat's `bandwidth:` and `panel_scaling:` and the density ridges' geom's
  (`GigRidges.DensityRidgeline`) beside Giggly's options for the marks: `scale:`, 1.8 unless given
  or mapped, so neighbouring ridges overlap, and `rel_min_height:`, the share of the layer's
  greatest height below which a point is left out, in place of the ridgeline's `min_height:`. A
  `scale` or `rel_min_height` mapped is each ridge's own.
  """
  @spec stat_density_ridges(Plot.t(), mapping() | keyword(), keyword()) :: Plot.t()
  def stat_density_ridges(plot, mapping_or_options \\ %{}, options \\ [])

  def stat_density_ridges(%Plot{} = plot, options, []) when is_list(options),
    do: stat_density_ridges(plot, %{}, options)

  def stat_density_ridges(%Plot{} = plot, mapping, options)
      when is_map(mapping) and is_list(options) do
    density_layer(plot, mapping, options, "GigRidges.stat_density_ridges/3")
  end

  @doc """
  Adds the layer `stat_density_ridges/3` adds, from the same mapping and options.
  """
  @spec geom_density_ridges(Plot.t(), mapping() | keyword(), keyword()) :: Plot.t()
  def geom_density_ridges(plot, mapping_or_options \\ %{}, options \\ [])

  def geom_density_ridges(%Plot{} = plot, options, []) when is_list(options),
    do: geom_density_ridges(plot, %{}, options)

  def geom_density_ridges(%Plot{} = plot, mapping, options)
      when is_map(mapping) and is_list(options) do
    density_layer(plot, mapping, options, "GigRidges.geom_density_ridges/3")
  end

  # A layer of density ridges, drawn by the density ridges' geom, 1.8 times their height unless
  # `scale` is given or mapped.
  defp density_layer(plot, mapping, options, function) do
    components = {GigRidges.DensityRidges, GigRidges.DensityRidgeline}
    layer(plot, mapping, options, components, function)
  end

  defp layer(plot, mapping, options, {stat, geom}, function),
    do: Plot.layer(plot, mapping, [stat: stat, geom: geom, function: function] ++ options)
end
