defmodule GigRidges.Ridgeline do
  @moduledoc """
  The ridgeline geom: each group a ridge along `x`, its baseline its `y` and its top `scale` times
  its `height` above it, filled down to the baseline and outlined along the top, drawn back to
  front so a lower ridge is drawn over the one above it.

  A point whose height is below `min_height` is left out of its ridge, which breaks there; with no
  `min_height`, a point below 0 is, and a point whose mapped `min_height` is missing is never cut
  off. The density ridges' geom (`GigRidges.DensityRidgeline`) cuts at `rel_min_height` times the
  layer's greatest height, across every panel, in its place.

  `scale` and `min_height` are each an option and an aesthetic: given as an option, its value is
  every point's; else a mapped column gives each point its own; else its default, a `scale` of 1,
  which the density ridges' geom makes 1.8, and a `min_height` of 0. The vertical ridgeline's geom
  (`GigRidges.VRidgeline`) draws through it turned, up `y`, its `width` and `min_width` in place
  of `height` and `min_height`.

  It draws by delegation to Giggly's ribbon (`Giggly.Geom.Ribbon`): its setup works out each
  point's `ymin` and `ymax` and hands the rows to the ribbon's setup, and each ridge is drawn by the
  ribbon, as is its legend key, which needs room as wide as its line, as ggridges' keys do, where
  the ribbon's needs twice that. Rows whose `datatype` is `"vline"`, the quantile lines the density
  ridges' stat writes, are kept from the ribbon and drawn as lines from each ridge's baseline up
  to it, between its fill and its top line, in the ridge's colour, line width and line type, or in
  the `vline_color:` (or `vline_colour:`), `vline_width:` and `vline_linetype:` given, each over
  the ridge's own, as ggridges' `vline_*` set them.
  """

  use Giggly.Geom

  alias Giggly.{DataFrame, Geom}
  alias GigRidges.{Gradient, LineStyle}

  # Points, 1/72 inch, in a millimetre, as key sizes are given.
  @points_per_millimetre 72 / 25.4

  # `cut_off`, `rel_min_height` and `unmapped_scale` are no options of the ridgeline's, but set by
  # the density ridges' geom, which builds the struct itself: the aesthetic a point is cut off by,
  # `:min_height` here and `:rel_min_height` there, a share of the layer's greatest height, given
  # or mapped there; and the scale a point takes where neither the option nor a mapping gives one,
  # 1 here and 1.8 there. The cut-off it is not cut by is ignored, mapped or not, as ggridges'
  # ridgeline ignores `rel_min_height` and its density ridges `min_height`. `iscaled` is whether
  # each point's height is first multiplied by its `iscale` column, which the density ridges' geom
  # writes, so the tallest reaches the next baseline. `outline` is the ribbon's outline type, the
  # top alone here and the whole border under the closed density ridges' geom. `along` is the axis
  # the ridges run along, `x` here and `y` under the vertical ridgeline's geom
  # (`GigRidges.VRidgeline`), whose ridges reach `scale` times their `width` beyond their `x`, cut
  # off by `min_width`, which `min_height` holds then. `gradient` is `:none`, or, under the gradient
  # ridgelines' geoms, the width in millimetres of the outline round each piece of one fill that a
  # ridge whose fill varies is drawn in (`GigRidges.Gradient`).
  defstruct scale: :none,
            min_height: :none,
            rel_min_height: :none,
            cut_off: :min_height,
            unmapped_scale: 1.0,
            iscaled: false,
            outline: :upper,
            along: :x,
            gradient: :none,
            vline_color: :unset,
            vline_colour: :unset,
            vline_width: :unset,
            vline_linetype: :unset

  @type t :: %__MODULE__{
          scale: :none | float(),
          min_height: :none | float(),
          rel_min_height: :none | float(),
          cut_off: :min_height | :rel_min_height | :min_width,
          unmapped_scale: float(),
          iscaled: boolean(),
          outline: :upper | :full,
          along: :x | :y,
          gradient: :none | float(),
          vline_color: :unset | String.t() | :none,
          vline_colour: :unset | String.t() | :none,
          vline_width: :unset | float(),
          vline_linetype: :unset | tuple() | :none
        }

  @impl Giggly.Geom
  def options do
    [
      scale: [
        type: {:custom, __MODULE__, :validate_scale, []},
        default: :none,
        doc:
          "How many times its `height` each ridge reaches above its baseline, a number above 0, " <>
            "every point's, over a mapped `scale`; 1 where neither gives one."
      ],
      min_height: [
        type: {:custom, __MODULE__, :validate_number, []},
        default: :none,
        doc:
          "The height below which a point is left out of its ridge, every point's, over a " <>
            "mapped `min_height`; 0 where neither gives one."
      ]
    ] ++ LineStyle.vline_options()
  end

  # `vline_color:` and `vline_colour:` given at once.
  @impl Giggly.Geom
  def option_conflicts(options), do: LineStyle.vline_conflicts(options)

  @impl Giggly.Geom
  def accepted_aesthetics(%__MODULE__{cut_off: cut_off, along: along}),
    do: [
      :x,
      :y,
      columns(along).size,
      :scale,
      cut_off,
      :group,
      :alpha,
      :color,
      :fill,
      :linetype,
      :linewidth
    ]

  @impl Giggly.Geom
  def required_aesthetics(%__MODULE__{along: along}), do: [:x, :y, columns(along).size]

  @impl Giggly.Geom
  def numeric_aesthetics(%__MODULE__{cut_off: cut_off, along: along}),
    do: [
      {columns(along).size, size_reason(along)},
      {:scale, "it is how many times its #{columns(along).size} each point reaches"},
      {cut_off, cut_off_reason(cut_off)}
    ]

  @impl Giggly.Geom
  def written_aesthetics(%__MODULE__{along: along}),
    do: [columns(along).low, columns(along).high]

  @doc false
  @spec validate_scale(term()) :: {:ok, :none | float()} | {:error, String.t()}
  def validate_scale(:none), do: {:ok, :none}
  def validate_scale(scale) when is_number(scale) and scale > 0, do: {:ok, scale / 1}
  def validate_scale(other), do: {:error, "expected a number above 0, got: #{inspect(other)}"}

  @doc false
  @spec validate_number(term()) :: {:ok, :none | float()} | {:error, String.t()}
  def validate_number(:none), do: {:ok, :none}
  def validate_number(number) when is_number(number), do: {:ok, number / 1}
  def validate_number(other), do: {:error, "expected a number, got: #{inspect(other)}"}

  # The ribbon's defaults, but a fill of R's grey70, grey80 for the vertical ridgeline's, and a
  # black top line half a millimetre wide, whatever the theme's ink and paper, as ggridges'
  # ridgelines take them. A theme's geom fill and colour replace them, as they do every Giggly
  # geom's (`Giggly.Geom.default_aesthetics/2`) and ggplot2's own geoms': a departure from ggridges
  # 0.5.7, which keeps grey70 and black.
  @impl Giggly.Geom
  def default_aesthetics(ridgeline, element) do
    ridgeline
    |> ribbon()
    |> Geom.default_aesthetics(element)
    |> Keyword.merge(fill: fill(ridgeline.along), color: "#000000", linewidth: 0.5)
  end

  @impl Giggly.Geom
  def setup_data(ridgeline, frame, axis_types) do
    columns = columns(ridgeline.along)
    heights = heights(ridgeline, frame)
    greatest = greatest(heights)

    {lows, highs} =
      [
        DataFrame.pull(frame, columns.baseline),
        heights,
        each_point(ridgeline.scale, frame, :scale, ridgeline.unmapped_scale),
        cut_offs(ridgeline, frame, greatest)
      ]
      |> Enum.zip_with(fn [baseline, height, scale, least] ->
        if Enum.all?([baseline, height, scale], &is_number/1) and
             (is_nil(least) or height >= least),
           do: {baseline, baseline + scale * height},
           else: {nil, nil}
      end)
      |> Enum.unzip()

    ranged =
      frame
      |> DataFrame.put(columns.low, lows)
      |> DataFrame.put(columns.high, highs)

    {ridges, lines} = line_rows(ranged)
    set_up = Geom.setup_data(ribbon(ridgeline), DataFrame.slice(ranged, ridges), axis_types)
    DataFrame.concat_rows([set_up, beside(DataFrame.slice(ranged, lines), set_up)])
  end

  # Which of the rows are a ridge's points and which the quantile lines up it the density ridges'
  # stat writes, whose `datatype` is `"vline"`, by their indices.
  defp line_rows(frame) do
    types =
      if :datatype in DataFrame.names(frame),
        do: DataFrame.pull(frame, :datatype),
        else: List.duplicate("ridgeline", DataFrame.row_count(frame))

    {lines, ridges} =
      types
      |> Enum.with_index()
      |> Enum.split_with(fn {type, _index} -> type == "vline" end)

    {Enum.map(ridges, &elem(&1, 1)), Enum.map(lines, &elem(&1, 1))}
  end

  # The line rows beside the ridges' set up, with each column the ridges' setup added, its first
  # row's value.
  defp beside(lines, set_up) do
    count = DataFrame.row_count(lines)

    (DataFrame.names(set_up) -- DataFrame.names(lines))
    |> Enum.reduce(lines, fn name, filled ->
      first = set_up |> DataFrame.pull(name) |> List.first()
      DataFrame.put(filled, name, List.duplicate(first, count))
    end)
  end

  # Each ridge drawn by the ribbon, the highest baseline first, so a lower ridge is drawn over
  # the one above it.
  @impl Giggly.Geom
  def draw_panel(ridgeline, frame, context) do
    frame
    |> DataFrame.split(:group)
    |> Map.values()
    |> Enum.sort_by(&baseline(&1, columns(ridgeline.along).low), :desc)
    |> Enum.flat_map(fn ridge -> draw_ridge(ridgeline, ridge, context) end)
  end

  @impl Giggly.Geom
  def draw_key(ridgeline, key, context), do: Geom.draw_key(ribbon(ridgeline), key, context)
  @impl Giggly.Geom
  # The room a key needs: a square as wide as its line, as ggridges' keys take it, where the
  # ribbon's takes twice that, as ggplot2's polygon keys do, and ggridges' vertical ridgeline's.
  def key_size(%__MODULE__{along: :y} = ridgeline, key, context),
    do: Geom.key_size(ribbon(ridgeline), key, context)

  def key_size(_ridgeline, key, _context) do
    side =
      case Map.fetch!(key, :linewidth) do
        nil -> 0.0
        line_width -> line_width * @points_per_millimetre
      end

    {side, side}
  end

  # A ridge drawn by the ribbon, or in pieces of one fill each under the gradient ridgelines' geoms.
  # A ridge with its quantile lines, if any: its fill, then its lines, then its top line over
  # them; or, outlined round under the closed density ridges' geom, its outlined fill, then its
  # lines, as ggridges draws them.
  defp draw_ridge(ridgeline, ridge, context) do
    case line_rows(ridge) do
      {_points, []} ->
        body(ridgeline, ridge, context)

      {points, lines} ->
        lined(
          ridgeline,
          DataFrame.slice(ridge, points),
          quantile_lines(ridgeline, ridge, lines),
          context
        )
    end
  end

  defp body(%__MODULE__{gradient: :none} = ridgeline, ridge, context),
    do: Geom.draw_panel(ribbon(ridgeline), ridge, context)

  defp body(%__MODULE__{gradient: width}, ridge, context),
    do: Gradient.pieces(ridge, width, context) ++ top(ridge, context)

  defp lined(%__MODULE__{outline: :full} = ridgeline, ridge, drawn_lines, context),
    do: Geom.draw_panel(ribbon(ridgeline), ridge, context) ++ drawn_lines.(context)

  defp lined(%__MODULE__{gradient: :none} = ridgeline, ridge, drawn_lines, context) do
    unoutlined = DataFrame.put(ridge, :linewidth, List.duplicate(nil, DataFrame.row_count(ridge)))

    Geom.draw_panel(ribbon(ridgeline), unoutlined, context) ++
      drawn_lines.(context) ++ top(ridge, context)
  end

  defp lined(%__MODULE__{gradient: width}, ridge, drawn_lines, context),
    do: Gradient.pieces(ridge, width, context) ++ drawn_lines.(context) ++ top(ridge, context)

  # The quantile lines of a ridge, from its baseline up to it, drawn in its own look, or the
  # `vline_*` options' where given, those of no place on the ridge left out.
  defp quantile_lines(ridgeline, ridge, indices) do
    fn context ->
      lines = DataFrame.slice(ridge, indices)
      tops = DataFrame.pull(lines, :ymax)
      drawn = for {top, index} <- Enum.with_index(tops), is_number(top), do: index
      count = length(drawn)

      rows =
        ridgeline
        |> Map.from_struct()
        |> LineStyle.vline_style()
        |> Enum.reduce(DataFrame.slice(lines, drawn), fn {column, value}, styled ->
          DataFrame.put(styled, column, List.duplicate(value, count))
        end)

      segments =
        rows
        |> DataFrame.put(:y, DataFrame.pull(rows, :ymin))
        |> DataFrame.put(:xend, DataFrame.pull(rows, :x))
        |> DataFrame.put(:yend, DataFrame.pull(rows, :ymax))

      Geom.draw_panel(Geom.new(Geom.Segment, []), segments, context)
    end
  end

  # A ridge's top, a line through each point's upper end in the ridge's own look.
  defp top(ridge, context) do
    line = DataFrame.put(ridge, :y, DataFrame.pull(ridge, :ymax))
    Geom.draw_panel(Geom.new(Geom.Path, linejoin: :round), line, context)
  end

  # Each point's height, times its `iscale` under the density ridges' geom; missing where either
  # is.
  defp heights(%__MODULE__{iscaled: false, along: along}, frame),
    do: DataFrame.pull(frame, columns(along).size)

  defp heights(%__MODULE__{iscaled: true}, frame) do
    frame
    |> DataFrame.pull(:height)
    |> Enum.zip_with(DataFrame.pull(frame, :iscale), fn
      height, iscale when is_number(height) and is_number(iscale) -> height * iscale
      _height, _iscale -> nil
    end)
  end

  # The layer's greatest height, 0 where it has none.
  defp greatest(heights) do
    heights
    |> Enum.filter(&is_number/1)
    |> Enum.max(fn -> 0.0 end)
  end

  # Each point's cut-off, the height below which it is left out: its `min_height`, 0 where none is
  # given or mapped; or, under the density ridges' geom, its `rel_min_height` times the layer's
  # greatest height, 0 where none is. A mapped value missing is `nil`, no cut-off at all.
  defp cut_offs(%__MODULE__{cut_off: cut_off} = ridgeline, frame, _greatest)
       when cut_off in [:min_height, :min_width],
       do: each_point(ridgeline.min_height, frame, cut_off, 0.0)

  defp cut_offs(%__MODULE__{cut_off: :rel_min_height} = ridgeline, frame, greatest) do
    ridgeline.rel_min_height
    |> each_point(frame, :rel_min_height, 0.0)
    |> Enum.map(fn
      share when is_number(share) -> share * greatest
      missing -> missing
    end)
  end

  defp cut_off_reason(:min_height), do: "it is the height below which a point is left out"
  defp cut_off_reason(:min_width), do: "it is the width below which a point is left out"

  defp cut_off_reason(:rel_min_height),
    do: "it is the share of the greatest height below which a point is left out"

  # Each point's value of `name`: the option's where given, else the mapped column's, else the
  # default, as ggplot2 lays a set value over a mapped one and fills an unmapped one.
  defp each_point(:none, frame, name, default) do
    if name in DataFrame.names(frame),
      do: DataFrame.pull(frame, name),
      else: List.duplicate(default, DataFrame.row_count(frame))
  end

  defp each_point(given, frame, _name, _default),
    do: List.duplicate(given, DataFrame.row_count(frame))

  # A ridge's baseline, the least of its points' lower ends, minus infinity for a ridge left
  # with none.
  defp baseline(ridge, low) do
    ridge
    |> DataFrame.pull(low)
    |> Enum.filter(&is_number/1)
    |> Enum.min(fn -> :neg_infinity end)
  end

  # The columns a ridgeline along `x` or along `y` reads and writes: its baselines, its sizes and
  # the two ends of each point's range.
  defp columns(:x), do: %{baseline: :y, size: :height, low: :ymin, high: :ymax}
  defp columns(:y), do: %{baseline: :x, size: :width, low: :xmin, high: :xmax}

  defp size_reason(:x), do: "it is how far each ridge reaches above its y"
  defp size_reason(:y), do: "it is how far each ridge reaches beyond its x"

  # R's grey70, ggridges' ridgelines' fill, and grey80, its vertical ridgeline's.
  defp fill(:x), do: "#B3B3B3"
  defp fill(:y), do: "#CCCCCC"

  # The ribbon a ridge is set up and drawn by: along its axis, outlined along its top alone, or
  # round its whole border under the closed density ridges' geom.
  defp ribbon(%__MODULE__{outline: outline, along: along}),
    do: Geom.new(Geom.Ribbon, orientation: along, outline_type: outline, linejoin: :round)
end
