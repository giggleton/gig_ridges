defmodule GigRidges do
  @moduledoc """
  Ridgeline plots for Giggly: ridges along `x`, one above each baseline, as joy plots draw them.

  `geom_ridgeline/3` draws ridges of the heights a table gives, and `geom_vridgeline/3` of the
  widths it gives, running up `y`; `stat_density_ridges/3` and
  `geom_density_ridges/3` estimate each group's density along `x` and draw it as a ridge, and
  `geom_density_ridges2/3` draws it outlined round its whole border; `geom_density_line/3` draws
  one density over a baseline of 0 the way the ridges are drawn; `stat_binline/3` draws each
  group's histogram as a ridge; `geom_ridgeline_gradient/3` and `geom_density_ridges_gradient/3`
  draw a ridge whose fill varies along it. Each
  adds a layer to a `Giggly.Plot`, through `Giggly.Plot.layer/3`, so it takes Giggly's own options
  for the marks (`fill:`, `alpha:`, `colour:`, `linewidth:`, `linetype:`, `position:`) beside its
  own, and its mistakes are refused naming it. `cyclical_scale/3` and the `scale_*_cyclical/2`
  functions give the ridges values in turn, as alternating fills, through Giggly's manual scales,
  and `theme_ridges/2` draws everything but the marks as ggridges' `theme_ridges()` does.

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
  Adds the layer `geom_ridgeline/3` adds, from the same mapping and options, but a ridge whose
  `fill` varies along it drawn in pieces of one fill each (`GigRidges.RidgelineGradient`), as
  `%{fill: :x}` fills each ridge by where along it each point is.

  It takes `gradient_lwd:` beside the ridgeline's options: the width of each piece's outline in
  its own fill, in R's line-width units, 0.5 unless given, so the seams between pieces do not
  show.
  """
  @spec geom_ridgeline_gradient(Plot.t(), mapping() | keyword(), keyword()) :: Plot.t()
  def geom_ridgeline_gradient(plot, mapping_or_options \\ %{}, options \\ [])

  def geom_ridgeline_gradient(%Plot{} = plot, options, []) when is_list(options),
    do: geom_ridgeline_gradient(plot, %{}, options)

  def geom_ridgeline_gradient(%Plot{} = plot, mapping, options)
      when is_map(mapping) and is_list(options) do
    components = {:identity, GigRidges.RidgelineGradient}
    layer(plot, mapping, options, components, "GigRidges.geom_ridgeline_gradient/3")
  end

  @doc """
  Adds a layer of vertical ridgelines: each group a ridge up `y`, its baseline its `x` and its
  outer edge `scale` times its `width` beyond it (`GigRidges.VRidgeline`), the rows drawn as they
  are.

  It needs `:x`, `:y` and `:width`, and takes `scale:` and `min_width:` beside Giggly's options
  for the marks; each may be mapped instead, giving each point its own, an option given beating
  its mapping.

      iex> frame =
      ...>   %{"x" => [0, 0, 0, 1, 1, 1], "y" => [1, 2, 3, 1, 2, 3], "w" => [0.2, 0.9, 0.3, 0.5, 0.4, 0.1]}
      ...>   |> Giggly.Plot.new(%{x: :x, y: :y, width: :w, group: :x})
      ...>   |> GigRidges.geom_vridgeline(scale: 2)
      ...>   |> Giggly.layer_data()
      iex> Giggly.DataFrame.pull(frame, :xmax)
      [0.4, 1.8, 0.6, 2.0, 1.8, 1.2]
  """
  @spec geom_vridgeline(Plot.t(), mapping() | keyword(), keyword()) :: Plot.t()
  def geom_vridgeline(plot, mapping_or_options \\ %{}, options \\ [])

  def geom_vridgeline(%Plot{} = plot, options, []) when is_list(options),
    do: geom_vridgeline(plot, %{}, options)

  def geom_vridgeline(%Plot{} = plot, mapping, options)
      when is_map(mapping) and is_list(options) do
    layer(
      plot,
      mapping,
      options,
      {:identity, GigRidges.VRidgeline},
      "GigRidges.geom_vridgeline/3"
    )
  end

  @doc """
  Adds a layer of density ridges: each group's density along `x`, estimated with one bandwidth
  each panel's groups share (`GigRidges.DensityRidges`), drawn as a ridgeline above its `y`, so the
  panel's greatest density reaches the next baseline at a `scale:` of 1.

  It needs `:x` and `:y`, `y` most often a discrete column whose values name the ridges, and takes
  the stat's `bandwidth:`; `from:`, `to:` and `n:`, the span and number of places each density is
  read at; and `quantile_lines:`, `quantiles:` and `quantile_fun:`, a line up each ridge at each of
  its group's quantiles, or under `calc_ecdf:` each place's `ecdf` and band alone;
  `jittered_points:`, a point under each ridge at each of its group's values, drawn in the `point_*`
  given, on its baseline unless the layer's position moves it, as `GigRidges.PointsSina`,
  `GigRidges.PointsJitter` and `GigRidges.PointsRaincloud` do; the lines drawn in the `vline_color:`, `vline_width:` and `vline_linetype:` given, over the
  ridge's own; and the density ridges' geom's (`GigRidges.DensityRidgeline`) beside Giggly's options
  for the marks: `scale:`, 1.8 unless given or mapped, so neighbouring ridges overlap;
  `panel_scaling:`, whether each panel's tallest ridge or the layer's reaches the next baseline; and
  `rel_min_height:`, the share of the layer's greatest height below which a point is left out, in
  place of the ridgeline's `min_height:`. A `scale` or `rel_min_height` mapped is each ridge's own,
  and a `weight` mapped weighs each row's share of its group's density.
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
  Adds the layer `stat_density_ridges/3` adds, from the same mapping and options, but its points
  under `jittered_points:` set up their ridges at random (`GigRidges.PointsSina`) unless another
  `position:` is given, as ggridges' `geom_density_ridges()` takes `position_points_sina()`,
  where the stat's stay on their baselines.
  """
  @spec geom_density_ridges(Plot.t(), mapping() | keyword(), keyword()) :: Plot.t()
  def geom_density_ridges(plot, mapping_or_options \\ %{}, options \\ [])

  def geom_density_ridges(%Plot{} = plot, options, []) when is_list(options),
    do: geom_density_ridges(plot, %{}, options)

  def geom_density_ridges(%Plot{} = plot, mapping, options)
      when is_map(mapping) and is_list(options) do
    density_layer(plot, mapping, sina(options), "GigRidges.geom_density_ridges/3")
  end

  @doc """
  Adds the layer `geom_density_ridges/3` adds, from the same mapping and options, but a ridge
  whose `fill` varies along it drawn in pieces of one fill each
  (`GigRidges.DensityRidgelineGradient`), as `%{fill: {:after_stat, [:x]}}` fills each ridge by
  where along it each place is; and `gradient_lwd:`, each piece's outline in its own fill, 0.5
  unless given.
  """
  @spec geom_density_ridges_gradient(Plot.t(), mapping() | keyword(), keyword()) :: Plot.t()
  def geom_density_ridges_gradient(plot, mapping_or_options \\ %{}, options \\ [])

  def geom_density_ridges_gradient(%Plot{} = plot, options, []) when is_list(options),
    do: geom_density_ridges_gradient(plot, %{}, options)

  def geom_density_ridges_gradient(%Plot{} = plot, mapping, options)
      when is_map(mapping) and is_list(options) do
    components = {GigRidges.DensityRidges, GigRidges.DensityRidgelineGradient}
    layer(plot, mapping, sina(options), components, "GigRidges.geom_density_ridges_gradient/3")
  end

  @doc """
  Adds a layer of binned ridges: each group's values counted in bins along `x`, every group of a
  panel in the panel's bins (`GigRidges.Binline`), drawn by the density ridges' geom as a
  histogram's outline above its `y`, so the panel's greatest density reaches the next baseline
  at a `scale:` of 1.

  It needs `:x` and `:y`, and takes the stat's `binwidth:`, `bins:`, `center:`, `boundary:`,
  `breaks:`, `closed:`, `pad:` and `draw_baseline:`, and the density ridges' geom's `scale:`,
  `rel_min_height:` and `panel_scaling:`, beside Giggly's options for the marks.
  """
  @spec stat_binline(Plot.t(), mapping() | keyword(), keyword()) :: Plot.t()
  def stat_binline(plot, mapping_or_options \\ %{}, options \\ [])

  def stat_binline(%Plot{} = plot, options, []) when is_list(options),
    do: stat_binline(plot, %{}, options)

  def stat_binline(%Plot{} = plot, mapping, options)
      when is_map(mapping) and is_list(options) do
    components = {GigRidges.Binline, GigRidges.DensityRidgeline}
    layer(plot, mapping, options, components, "GigRidges.stat_binline/3")
  end

  @doc """
  Adds a layer of density lines: each group's density along `x`, estimated by Giggly's density
  stat (`Giggly.Plot.geom_density/3`'s), drawn as a ridgeline over a baseline of 0
  (`GigRidges.DensityLine`), filled grey70 and outlined in black along its top, where
  `Giggly.Plot.geom_density/3` is filled with nothing.

  It needs `:x`, and takes the density stat's options, `bw:`, `adjust:`, `kernel:`, `n:`, `trim:`
  and `bounds:`, beside Giggly's options for the marks; a mapped `y` reads another of the stat's
  variables, as `{:after_stat, [:count]}`.
  """
  @spec geom_density_line(Plot.t(), mapping() | keyword(), keyword()) :: Plot.t()
  def geom_density_line(plot, mapping_or_options \\ %{}, options \\ [])

  def geom_density_line(%Plot{} = plot, options, []) when is_list(options),
    do: geom_density_line(plot, %{}, options)

  def geom_density_line(%Plot{} = plot, mapping, options)
      when is_map(mapping) and is_list(options) do
    layer(
      plot,
      mapping,
      options,
      {:density, GigRidges.DensityLine},
      "GigRidges.geom_density_line/3"
    )
  end

  @doc """
  Adds the layer `geom_density_ridges/3` adds, from the same mapping and options, but each ridge
  outlined round its whole border, its baseline and sides too, not along its top alone
  (`GigRidges.DensityRidgeline2`).
  """
  @spec geom_density_ridges2(Plot.t(), mapping() | keyword(), keyword()) :: Plot.t()
  def geom_density_ridges2(plot, mapping_or_options \\ %{}, options \\ [])

  def geom_density_ridges2(%Plot{} = plot, options, []) when is_list(options),
    do: geom_density_ridges2(plot, %{}, options)

  def geom_density_ridges2(%Plot{} = plot, mapping, options)
      when is_map(mapping) and is_list(options) do
    components = {GigRidges.DensityRidges, GigRidges.DensityRidgeline2}
    layer(plot, mapping, sina(options), components, "GigRidges.geom_density_ridges2/3")
  end

  @doc """
  Gives the plot one cyclical scale serving every aesthetic `aesthetics` names, replacing any
  scale that served one of them, as ggridges' `cyclical_scale()`: `values:`, a list, handed to the
  data's values in the order the scale shows them and started again at the first once they run
  out, so the ridges take turns, as `values: ["red", "blue"]` fills five ridges red, blue, red,
  blue and red.

  It is Giggly's manual scale (`Giggly.Plot.scale_discrete_manual/3`), its values repeated, and
  takes its options, which check every value given as the aesthetics they serve check one, and
  its aesthetics, `:color` and `:fill` together, any of `:alpha`, `:size` and `:linewidth`, or
  `:linetype`, `:colour` spelled either way. Its legend is drawn only under `guide: :legend`,
  where `breaks:` chooses its keys, each drawn as its own value is, and `labels:` labels them, as
  `breaks: ["a", "b"], labels: ["odd", "even"]` labels a cycle of two. Its values are repeated to
  a thousand, or to as many as `limits:` gives, and a scale showing more refuses the plot, as a
  manual scale given too few values does. Raises `ArgumentError` for `values:` that are not a list
  of one value or more.

      iex> frame =
      ...>   %{"v" => [0, 1, 2, 0, 1, 2, 0, 1, 2], "g" => ~w(a a a b b b c c c)}
      ...>   |> Giggly.Plot.new(%{x: :v, y: :g, fill: :g, colour: :g})
      ...>   |> GigRidges.geom_density_ridges(bandwidth: 1)
      ...>   |> GigRidges.cyclical_scale([:fill, :colour], values: ["red", "blue"])
      ...>   |> Giggly.layer_data()
      iex> frame |> Giggly.DataFrame.pull(:fill) |> Enum.dedup()
      ["#FF0000", "#0000FF", "#FF0000"]
  """
  @spec cyclical_scale(Plot.t(), atom() | [atom()], keyword()) :: Plot.t()
  def cyclical_scale(%Plot{} = plot, aesthetics, options) when is_list(options),
    do: GigRidges.Cyclical.scale(plot, aesthetics, options, "GigRidges.cyclical_scale/3")

  @doc """
  Gives the plot a cyclical fill scale, replacing any fill scale it had: `cyclical_scale/3` serving
  `:fill`, as ggridges' `scale_fill_cyclical()`.

      iex> frame =
      ...>   %{"v" => [0, 1, 2, 0, 1, 2, 0, 1, 2], "g" => ~w(a a a b b b c c c)}
      ...>   |> Giggly.Plot.new(%{x: :v, y: :g, fill: :g})
      ...>   |> GigRidges.geom_density_ridges(bandwidth: 1)
      ...>   |> GigRidges.scale_fill_cyclical(values: ["red", "blue"])
      ...>   |> Giggly.layer_data()
      iex> frame |> Giggly.DataFrame.pull(:fill) |> Enum.dedup()
      ["#FF0000", "#0000FF", "#FF0000"]
  """
  @spec scale_fill_cyclical(Plot.t(), keyword()) :: Plot.t()
  def scale_fill_cyclical(%Plot{} = plot, options) when is_list(options),
    do: GigRidges.Cyclical.scale(plot, :fill, options, "GigRidges.scale_fill_cyclical/2")

  @doc """
  Gives the plot a cyclical colour scale, replacing any colour scale it had: `cyclical_scale/3`
  serving `:color`, as ggridges' `scale_colour_cyclical()`.
  """
  @spec scale_colour_cyclical(Plot.t(), keyword()) :: Plot.t()
  def scale_colour_cyclical(%Plot{} = plot, options) when is_list(options),
    do: GigRidges.Cyclical.scale(plot, :color, options, "GigRidges.scale_colour_cyclical/2")

  @doc "The cyclical colour scale `scale_colour_cyclical/2` gives, as ggridges' `scale_color_cyclical()`."
  @spec scale_color_cyclical(Plot.t(), keyword()) :: Plot.t()
  def scale_color_cyclical(%Plot{} = plot, options) when is_list(options),
    do: GigRidges.Cyclical.scale(plot, :color, options, "GigRidges.scale_color_cyclical/2")

  @doc """
  Gives the plot a cyclical alpha scale, replacing any alpha scale it had: `cyclical_scale/3`
  serving `:alpha`, as ggridges' `scale_alpha_cyclical()`.
  """
  @spec scale_alpha_cyclical(Plot.t(), keyword()) :: Plot.t()
  def scale_alpha_cyclical(%Plot{} = plot, options) when is_list(options),
    do: GigRidges.Cyclical.scale(plot, :alpha, options, "GigRidges.scale_alpha_cyclical/2")

  @doc """
  Gives the plot a cyclical line type scale, replacing any line type scale it had:
  `cyclical_scale/3` serving `:linetype`, as ggridges' `scale_linetype_cyclical()`.
  """
  @spec scale_linetype_cyclical(Plot.t(), keyword()) :: Plot.t()
  def scale_linetype_cyclical(%Plot{} = plot, options) when is_list(options),
    do: GigRidges.Cyclical.scale(plot, :linetype, options, "GigRidges.scale_linetype_cyclical/2")

  @doc """
  Gives the plot a cyclical line width scale, replacing any line width scale it had:
  `cyclical_scale/3` serving `:linewidth`, as ggridges' `scale_linewidth_cyclical()`.
  """
  @spec scale_linewidth_cyclical(Plot.t(), keyword()) :: Plot.t()
  def scale_linewidth_cyclical(%Plot{} = plot, options) when is_list(options),
    do:
      GigRidges.Cyclical.scale(plot, :linewidth, options, "GigRidges.scale_linewidth_cyclical/2")

  @doc """
  Gives the plot a cyclical size scale, replacing any size scale it had: `cyclical_scale/3`
  serving `:size`, as ggridges' `scale_size_cyclical()`.
  """
  @spec scale_size_cyclical(Plot.t(), keyword()) :: Plot.t()
  def scale_size_cyclical(%Plot{} = plot, options) when is_list(options),
    do: GigRidges.Cyclical.scale(plot, :size, options, "GigRidges.scale_size_cyclical/2")

  @doc """
  Draws everything but the marks as ggridges' `theme_ridges()` does, for ridgeline plots: nothing
  behind the marks, light grey grid lines and ticks, black text, the axes' titles at the far ends
  of their axes and the y axis's tick labels on their baselines, so each ridge's name sits on it.

  Given a plot, it replaces the plot's theme whole, as `Giggly.Plot.theme_gray/2` does; given its
  options alone, it returns the theme, to be kept and given to plots with `Giggly.Plot.theme/2`.
  It is Giggly's default theme at a base size of `font_size:`, with its settings laid over it, so
  a later `Giggly.Plot.theme/2` call is laid over it in turn.

  ## Options

  #{NimbleOptions.docs(GigRidges.RidgesTheme.options())}

      iex> svg =
      ...>   %{"v" => [0, 1, 2, 0, 1, 2], "g" => ~w(a a a b b b)}
      ...>   |> Giggly.Plot.new(%{x: :v, y: :g})
      ...>   |> GigRidges.geom_density_ridges(bandwidth: 1)
      ...>   |> GigRidges.theme_ridges(grid: false)
      ...>   |> Giggly.to_svg()
      ...>   |> IO.iodata_to_binary()
      iex> svg =~ "#E5E5E5"
      false
  """
  @spec theme_ridges(Plot.t() | keyword(), keyword()) :: Plot.t() | term()
  def theme_ridges(plot_or_options \\ [], options \\ [])

  def theme_ridges(%Plot{} = plot, options) when is_list(options),
    do: GigRidges.RidgesTheme.theme(plot, options)

  def theme_ridges(options, []) when is_list(options),
    do: GigRidges.RidgesTheme.theme(nil, options)

  # A layer of density ridges, drawn by the density ridges' geom, 1.8 times their height unless
  # `scale` is given or mapped.
  defp density_layer(plot, mapping, options, function) do
    components = {GigRidges.DensityRidges, GigRidges.DensityRidgeline}
    layer(plot, mapping, options, components, function)
  end

  # A density ridges geom's options, its points set up their ridges at random unless another
  # position is given.
  defp sina(options), do: Keyword.put_new(options, :position, GigRidges.PointsSina)

  defp layer(plot, mapping, options, {stat, geom}, function),
    do: Plot.layer(plot, mapping, [stat: stat, geom: geom, function: function] ++ options)
end
