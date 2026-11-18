defmodule GigRidges.Ridgeline do
  @moduledoc """
  The ridgeline geom: each group a ridge along `x`, its baseline its `y` and its top `scale` times
  its `height` above it, filled down to the baseline and outlined along the top, drawn back to
  front so a lower ridge is drawn over the one above it.

  A point whose height is below the cut-off is left out of its ridge, which breaks there: the
  cut-off is the larger of `min_height` and `rel_min_height` times the layer's greatest height.

  It draws by delegation to Giggly's ribbon (`Giggly.Geom.Ribbon`): its setup works out each
  point's `ymin` and `ymax` and hands the rows to the ribbon's setup, and each ridge is drawn by the
  ribbon, as is its legend key.
  """

  use Giggly.Geom

  alias Giggly.{DataFrame, Geom}

  defstruct scale: 1.0, min_height: 0.0, rel_min_height: 0.0

  @type t :: %__MODULE__{scale: float(), min_height: float(), rel_min_height: float()}

  @impl Giggly.Geom
  def options do
    [
      scale: [
        type: {:custom, __MODULE__, :validate_scale, []},
        default: 1.0,
        doc:
          "How many times its `height` each ridge reaches above its baseline, a number above 0."
      ],
      min_height: [
        type: {:custom, __MODULE__, :validate_number, []},
        default: 0.0,
        doc: "The height below which a point is left out of its ridge."
      ],
      rel_min_height: [
        type: {:custom, __MODULE__, :validate_share, []},
        default: 0.0,
        doc:
          "The height below which a point is left out of its ridge, as a share of the layer's " <>
            "greatest height, from 0 to 1."
      ]
    ]
  end

  @impl Giggly.Geom
  def accepted_aesthetics(_geom),
    do: [:x, :y, :height, :group, :alpha, :color, :fill, :linetype, :linewidth]

  @impl Giggly.Geom
  def required_aesthetics(_geom), do: [:x, :y, :height]

  @impl Giggly.Geom
  def numeric_aesthetics(_geom), do: [height: "it is how far each ridge reaches above its y"]

  @impl Giggly.Geom
  def written_aesthetics(_geom), do: [:ymin, :ymax]

  @doc false
  @spec validate_scale(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_scale(scale) when is_number(scale) and scale > 0, do: {:ok, scale / 1}
  def validate_scale(other), do: {:error, "expected a number above 0, got: #{inspect(other)}"}

  @doc false
  @spec validate_number(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_number(number) when is_number(number), do: {:ok, number / 1}
  def validate_number(other), do: {:error, "expected a number, got: #{inspect(other)}"}

  @doc false
  @spec validate_share(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_share(share) when is_number(share) and share >= 0 and share <= 1,
    do: {:ok, share / 1}

  def validate_share(other), do: {:error, "expected a number from 0 to 1, got: #{inspect(other)}"}

  # The ribbon's defaults, the top line in the theme's ink at its lines' width, so a ridge is
  # outlined along its top.
  @impl Giggly.Geom
  def default_aesthetics(_ridgeline, element) do
    ribbon()
    |> Geom.default_aesthetics(element)
    |> Keyword.merge(color: element.ink, linewidth: element.linewidth)
  end

  @impl Giggly.Geom
  def setup_data(ridgeline, frame, axis_types) do
    baselines = DataFrame.pull(frame, :y)
    heights = DataFrame.pull(frame, :height)
    cut_off = cut_off(ridgeline, heights)

    {lows, highs} =
      baselines
      |> Enum.zip_with(heights, fn baseline, height ->
        if is_number(baseline) and is_number(height) and height >= cut_off,
          do: {baseline, baseline + ridgeline.scale * height},
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

  # The height below which a point is left out of its ridge.
  defp cut_off(ridgeline, heights) do
    greatest =
      heights
      |> Enum.filter(&is_number/1)
      |> Enum.max(fn -> 0.0 end)

    max(ridgeline.min_height, ridgeline.rel_min_height * greatest)
  end

  # A ridge's baseline, the least of its points' lower ends, minus infinity for a ridge left
  # with none.
  defp baseline(ridge) do
    ridge
    |> DataFrame.pull(:ymin)
    |> Enum.filter(&is_number/1)
    |> Enum.min(fn -> :neg_infinity end)
  end

  # The ribbon a ridge is set up and drawn by: along x, outlined along its top alone.
  defp ribbon do
    Geom.Ribbon.new(
      orientation: :x,
      outline_type: :upper,
      lineend: :butt,
      linejoin: :round,
      linemitre: 10.0
    )
  end
end
