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
  which the density ridges' geom makes 1.8, and a `min_height` of 0.

  It draws by delegation to Giggly's ribbon (`Giggly.Geom.Ribbon`): its setup works out each
  point's `ymin` and `ymax` and hands the rows to the ribbon's setup, and each ridge is drawn by the
  ribbon, as is its legend key.
  """

  use Giggly.Geom

  alias Giggly.{DataFrame, Geom}

  # `cut_off`, `rel_min_height` and `unmapped_scale` are no options of the ridgeline's, but set by
  # the density ridges' geom, which builds the struct itself: the aesthetic a point is cut off by,
  # `:min_height` here and `:rel_min_height` there, a share of the layer's greatest height, given
  # or mapped there; and the scale a point takes where neither the option nor a mapping gives one,
  # 1 here and 1.8 there. The cut-off it is not cut by is ignored, mapped or not, as ggridges'
  # ridgeline ignores `rel_min_height` and its density ridges `min_height`.
  defstruct scale: :none,
            min_height: :none,
            rel_min_height: :none,
            cut_off: :min_height,
            unmapped_scale: 1.0

  @type t :: %__MODULE__{
          scale: :none | float(),
          min_height: :none | float(),
          rel_min_height: :none | float(),
          cut_off: :min_height | :rel_min_height,
          unmapped_scale: float()
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
    ]
  end

  @impl Giggly.Geom
  def accepted_aesthetics(%__MODULE__{cut_off: cut_off}),
    do: [
      :x,
      :y,
      :height,
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
  def required_aesthetics(_geom), do: [:x, :y, :height]

  @impl Giggly.Geom
  def numeric_aesthetics(%__MODULE__{cut_off: cut_off}),
    do: [
      {:height, "it is how far each ridge reaches above its y"},
      {:scale, "it is how many times its height each point reaches"},
      {cut_off, cut_off_reason(cut_off)}
    ]

  @impl Giggly.Geom
  def written_aesthetics(_geom), do: [:ymin, :ymax]

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

  # The ribbon's defaults, but a fill of R's grey70 and a black top line half a millimetre wide,
  # whatever the theme's ink and paper, as ggridges' ridgelines take them. A theme's geom fill and
  # colour replace them, as they do every Giggly geom's (`Giggly.Geom.default_aesthetics/2`) and
  # ggplot2's own geoms': a departure from ggridges 0.5.7, which keeps grey70 and black.
  @impl Giggly.Geom
  def default_aesthetics(_ridgeline, element) do
    ribbon()
    |> Geom.default_aesthetics(element)
    |> Keyword.merge(fill: "#B3B3B3", color: "#000000", linewidth: 0.5)
  end

  @impl Giggly.Geom
  def setup_data(ridgeline, frame, axis_types) do
    heights = DataFrame.pull(frame, :height)
    greatest = greatest(heights)

    {lows, highs} =
      [
        DataFrame.pull(frame, :y),
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
      |> DataFrame.put(:ymin, lows)
      |> DataFrame.put(:ymax, highs)

    Geom.setup_data(ribbon(), ranged, axis_types)
  end

  # Each ridge drawn by the ribbon, the highest baseline first, so a lower ridge is drawn over
  # the one above it.
  @impl Giggly.Geom
  def draw_panel(_ridgeline, frame, context) do
    frame
    |> DataFrame.split(:group)
    |> Map.values()
    |> Enum.sort_by(&baseline/1, :desc)
    |> Enum.flat_map(fn ridge -> Geom.draw_panel(ribbon(), ridge, context) end)
  end

  @impl Giggly.Geom
  def draw_key(_ridgeline, key, context), do: Geom.draw_key(ribbon(), key, context)
  @impl Giggly.Geom
  def key_size(_ridgeline, key, context), do: Geom.key_size(ribbon(), key, context)

  # The layer's greatest height, 0 where it has none.
  defp greatest(heights) do
    heights
    |> Enum.filter(&is_number/1)
    |> Enum.max(fn -> 0.0 end)
  end

  # Each point's cut-off, the height below which it is left out: its `min_height`, 0 where none is
  # given or mapped; or, under the density ridges' geom, its `rel_min_height` times the layer's
  # greatest height, 0 where none is. A mapped value missing is `nil`, no cut-off at all.
  defp cut_offs(%__MODULE__{cut_off: :min_height} = ridgeline, frame, _greatest),
    do: each_point(ridgeline.min_height, frame, :min_height, 0.0)

  defp cut_offs(%__MODULE__{cut_off: :rel_min_height} = ridgeline, frame, greatest) do
    ridgeline.rel_min_height
    |> each_point(frame, :rel_min_height, 0.0)
    |> Enum.map(fn
      share when is_number(share) -> share * greatest
      missing -> missing
    end)
  end

  defp cut_off_reason(:min_height), do: "it is the height below which a point is left out"

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
  defp baseline(ridge) do
    ridge
    |> DataFrame.pull(:ymin)
    |> Enum.filter(&is_number/1)
    |> Enum.min(fn -> :neg_infinity end)
  end

  # The ribbon a ridge is set up and drawn by: along x, outlined along its top alone.
  defp ribbon, do: Geom.new(Geom.Ribbon, orientation: :x, outline_type: :upper, linejoin: :round)
end
