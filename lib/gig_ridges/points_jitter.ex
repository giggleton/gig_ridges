defmodule GigRidges.PointsJitter do
  @moduledoc """
  The jittered points' jitter, ggridges' `position_points_jitter()`: each of the layer's points,
  its rows whose `datatype` is `"point"`, moved across by up to `width:` either way, 0 unless
  given, and set up from its baseline by `yoffset:`, 0 unless given, and up to `height:` either
  way, 0.2 unless given, in the units of the y axis, its `ymin` the height it is drawn at. Every
  other row stays where it is, but under `adjust_vlines:` the quantile lines, the rows whose
  `datatype` is `"vline"`, which then run across the band the points fall in, from `yoffset:`
  less `height:` above the baseline to `yoffset:` and `height:` above it.

  The distances come from random numbers drawn from `seed:`, 0 unless given, by Erlang's `exsss`
  algorithm, each panel drawing afresh from the seed, as Giggly's own jitter (`position:
  :jitter`) draws them: each point in turn draws two, across and then up, a draw `u` from 0 to 1
  becoming `-amount + 2 * amount * u`, as R's `runif()` scales one. R's own numbers are not
  reproduced, so the same seed draws other points than ggridges' does, within the same bands. A
  layer with no `datatype`, as a ridgeline's, is left as it is.

  It is given to a density ridges layer's `position:`, alone or with its options, as
  `position: {GigRidges.PointsJitter, height: 0.1, seed: 7}`.
  """

  use Giggly.Position

  alias Giggly.DataFrame

  defstruct width: 0.0, height: 0.2, yoffset: 0.0, adjust_vlines: false, seed: 0

  @type t :: %__MODULE__{
          width: float(),
          height: float(),
          yoffset: float(),
          adjust_vlines: boolean(),
          seed: integer()
        }

  @algorithm :exsss

  @impl Giggly.Position
  def options do
    [
      width: [
        type: {:custom, __MODULE__, :validate_amount, []},
        default: 0.0,
        doc: "How far each point moves at most across, either way, in the units of the x axis."
      ],
      height: [
        type: {:custom, __MODULE__, :validate_amount, []},
        default: 0.2,
        doc: "How far each point moves at most up or down, in the units of the y axis."
      ],
      yoffset: [
        type: {:custom, __MODULE__, :validate_offset, []},
        default: 0.0,
        doc:
          "How far above its baseline each point's band is centred, in the units of the y axis."
      ],
      adjust_vlines: [
        type: :boolean,
        default: false,
        doc: "Whether the quantile lines run across the points' band, not from the baseline up."
      ],
      seed: [
        type: :integer,
        default: 0,
        doc:
          "The seed the random distances are drawn from, any integer: the same seed moves the " <>
            "same points the same way, so another seed draws other distances."
      ]
    ]
  end

  @doc false
  @spec validate_amount(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_amount(amount) when is_number(amount) and amount >= 0, do: {:ok, amount / 1}

  def validate_amount(other),
    do: {:error, "expected a distance, a number of 0 or more, got: #{inspect(other)}"}

  @doc false
  @spec validate_offset(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_offset(offset) when is_number(offset), do: {:ok, offset / 1}
  def validate_offset(other), do: {:error, "expected a number, got: #{inspect(other)}"}

  @impl Giggly.Position
  def compute_layer(jitter, frame, _axis_types) do
    case :datatype in DataFrame.names(frame) do
      false -> frame
      true -> frame |> jittered(jitter) |> lined(jitter)
    end
  end

  # Each point moved across and up from its baseline, its own two draws from its panel's stream.
  defp jittered(frame, jitter) do
    types = DataFrame.pull(frame, :datatype)
    panels = DataFrame.pull(frame, :panel)
    xs = DataFrame.pull(frame, :x)
    ys = DataFrame.pull(frame, :y)
    lows = DataFrame.pull(frame, :ymin)

    {moved, _streams} =
      [types, panels, xs, ys, lows]
      |> Enum.zip()
      |> Enum.map_reduce(%{}, fn
        {"point", panel, x, y, _low}, streams ->
          stream = Map.get_lazy(streams, panel, fn -> :rand.seed_s(@algorithm, jitter.seed) end)
          {across, stream} = :rand.uniform_s(stream)
          {up, stream} = :rand.uniform_s(stream)
          dx = distance(across, jitter.width)
          dy = jitter.yoffset + distance(up, jitter.height)
          {{x + dx, y + dy}, Map.put(streams, panel, stream)}

        {_type, _panel, x, _y, low}, streams ->
          {{x, low}, streams}
      end)

    {xs, lows} = Enum.unzip(moved)

    frame
    |> DataFrame.put(:x, xs)
    |> DataFrame.put(:ymin, lows)
  end

  # Under `adjust_vlines:`, each quantile line across the points' band above its baseline.
  defp lined(frame, %__MODULE__{adjust_vlines: false}), do: frame

  defp lined(frame, jitter) do
    low = jitter.yoffset - jitter.height
    high = jitter.yoffset + jitter.height

    {lows, highs} =
      [DataFrame.pull(frame, :datatype), DataFrame.pull(frame, :y)]
      |> Enum.zip()
      |> Enum.zip(Enum.zip(DataFrame.pull(frame, :ymin), DataFrame.pull(frame, :ymax)))
      |> Enum.map(fn
        {{"vline", y}, _range} -> {y + low, y + high}
        {_row, range} -> range
      end)
      |> Enum.unzip()

    frame
    |> DataFrame.put(:ymin, lows)
    |> DataFrame.put(:ymax, highs)
  end

  # R's `runif(1, -amount, amount)` for the draw `draw`: `min + (max - min) * draw`.
  defp distance(draw, amount), do: -amount + 2 * amount * draw
end
