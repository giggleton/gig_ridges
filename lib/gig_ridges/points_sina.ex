defmodule GigRidges.PointsSina do
  @moduledoc """
  The jittered points' sina, which the density ridges' geoms
  take unless given another position: each of the layer's points, its rows whose `datatype` is
  `"point"`, set up from its baseline by a random share of its ridge's height there, from
  `ymin` at its baseline to `ymax` at the ridge's top, so the points fill the ridge as its
  density does. The share runs from `rel_min:` to `rel_max:`, 0.02 and 0.98 unless given, and is
  the point's `ymin`, the height it is drawn at; its `x` and every other row stay where they are.

  A `rel_min:` above `rel_max:` is refused.

  The shares come from random numbers drawn from `seed:`, 0 unless given, as
  `GigRidges.PointsJitter` draws its distances, one for each point: a draw `u` from 0 to 1
  becoming `rel_min + (rel_max - rel_min) * u`. R's own numbers are not reproduced, so the same
  seed draws other points than R would, within the same bands. A layer with no
  `datatype`, as a ridgeline's, is left as it is.

  It is given to a layer's `position:`, alone or with its options, as `position:
  {GigRidges.PointsSina, rel_max: 0.5, seed: 7}`.
  """

  # ggridges' `position_points_sina()`. Departure: ggridges 0.5.7 sets each share between 0.02
  # and `rel_max`, whatever `rel_min` it is given; gig_ridges sets it between `rel_min:` and
  # `rel_max:`, the same at the default 0.02.

  use Giggly.Position

  alias Giggly.DataFrame
  alias GigRidges.Draws

  defstruct rel_min: 0.02, rel_max: 0.98, seed: 0

  @type t :: %__MODULE__{rel_min: float(), rel_max: float(), seed: integer()}

  @impl Giggly.Position
  def options do
    [
      rel_min: [
        type: {:custom, __MODULE__, :validate_share, []},
        default: 0.02,
        doc: "The least share of its ridge's height each point is set up by, from 0 to 1."
      ],
      rel_max: [
        type: {:custom, __MODULE__, :validate_share, []},
        default: 0.98,
        doc: "The greatest share of its ridge's height each point is set up by, from 0 to 1."
      ],
      seed: [
        type: :integer,
        default: 0,
        doc:
          "The seed the random shares are drawn from, any integer: the same seed sets the same " <>
            "points the same way, so another seed draws other shares."
      ]
    ]
  end

  @doc false
  @spec validate_share(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_share(share) when is_number(share) and share >= 0 and share <= 1,
    do: {:ok, share / 1}

  def validate_share(other),
    do: {:error, "expected a share, a number from 0 to 1, got: #{inspect(other)}"}

  # The least share above the greatest would set no point within the band they bound.
  @impl Giggly.Position
  def new(options) do
    sina = struct!(__MODULE__, Keyword.take(options, [:rel_min, :rel_max, :seed]))

    if sina.rel_min > sina.rel_max do
      raise ArgumentError,
            "GigRidges.PointsSina takes a rel_min: of at most its rel_max:, got rel_min: " <>
              "#{sina.rel_min} and rel_max: #{sina.rel_max}"
    end

    sina
  end

  @impl Giggly.Position
  def compute_layer(sina, frame, _axis_types) do
    case :datatype in DataFrame.names(frame) do
      false -> frame
      true -> DataFrame.put(frame, :ymin, set(frame, sina))
    end
  end

  # Each point's `ymin`, its share of its ridge's height up from its baseline; every other row's
  # as it was, and a point's with no height to share, as a missing `scale` leaves one.
  defp set(frame, sina) do
    [
      Draws.points(frame, sina.seed, 1),
      DataFrame.pull(frame, :y),
      DataFrame.pull(frame, :ymin),
      DataFrame.pull(frame, :ymax)
    ]
    |> Enum.zip_with(fn
      [[draw], y, _low, top] when is_number(top) ->
        y + (sina.rel_min + (sina.rel_max - sina.rel_min) * draw) * (top - y)

      [_draws, _y, low, _top] ->
        low
    end)
  end
end
